module controller (input  logic       clk,
                   input  logic       reset,
                   input  logic [6:0] op,
                   input  logic [2:0] funct3,
                   input  logic       funct7b5,
                   input  logic       zero,
                   output logic [1:0] immsrc,
                   output logic [1:0] alusrca, alusrcb,
                   output logic [1:0] resultsrc,
                   output logic       adrsrc,
                   output logic [2:0] alucontrol,
                   output logic       irwrite, pcwrite,
                   output logic       regwrite, memwrite);

  logic [1:0] aluop;
  
  logic       branch;
  logic       pcupdate;

  mainfsm fsm (.clk(clk), .reset(reset), .op(op), 
               .ResultSrc(resultsrc), .MemWrite(memwrite), .IRWrite(irwrite), 
               .ALUSrcA(alusrca), .ALUSrcB(alusrcb), .AdrSrc(adrsrc), 
               .PCUpdate(pcupdate), .Branch(branch), .RegWrite(regwrite), 
               .ALUOp(aluop));

  aludec  ad  (.opb5(op[5]), .funct3(funct3), .funct7b5(funct7b5), 
               .ALUOp(aluop), .ALUControl(alucontrol));

  instrdec id (.op(op), .ImmSrc(immsrc));

  assign pcwrite = (branch & zero) | pcupdate;

endmodule

module instrdec (input  logic [6:0] op,
                 output logic [1:0] ImmSrc);

  always_comb
    case(op)
      7'b0110011: ImmSrc = 2'bxx; // R-type (No immediate used)
      7'b0010011: ImmSrc = 2'b00; // I-type ALU (e.g., addi)
      7'b0000011: ImmSrc = 2'b00; // lw (Load Word)
      7'b0100011: ImmSrc = 2'b01; // sw (Store Word)
      7'b1100011: ImmSrc = 2'b10; // beq (Branch)
      7'b1101111: ImmSrc = 2'b11; // jal (Jump and Link)
      default:    ImmSrc = 2'bxx; // Unknown instruction
    endcase

endmodule

module aludec (input  logic       opb5,
               input  logic [2:0] funct3,
               input  logic       funct7b5,
               input  logic [1:0] ALUOp,
               output logic [2:0] ALUControl);

  logic RtypeSub;
  
  // Flag to identify an R-type subtract instruction
  assign RtypeSub = funct7b5 & opb5; 

  always_comb
    case(ALUOp)
      // Mapped to match controller.tv (MIPS-style)
      2'b00:                ALUControl = 3'b010; // ADD
      2'b01:                ALUControl = 3'b110; // SUB
      default: case(funct3) 
                 3'b000:  if (RtypeSub) 
                            ALUControl = 3'b110; // SUB
                          else          
                            ALUControl = 3'b010; // ADD
                 3'b010:    ALUControl = 3'b111; // SLT
                 3'b110:    ALUControl = 3'b001; // OR
                 3'b111:    ALUControl = 3'b000; // AND
                 default:   ALUControl = 3'bxxx; 
               endcase
    endcase
endmodule

module mainfsm (input  logic       clk,
                input  logic       reset,
                input  logic [6:0] op,
                output logic [1:0] ResultSrc,
                output logic       MemWrite,
                output logic       IRWrite,
                output logic [1:0] ALUSrcA,
                output logic [1:0] ALUSrcB,
                output logic       AdrSrc,
                output logic       PCUpdate,
                output logic       Branch,
                output logic       RegWrite,
                output logic [1:0] ALUOp);

  // Define the states exactly as shown in Figure 2
  typedef enum logic [3:0] {
    FETCH    = 4'd0,
    DECODE   = 4'd1,
    MEMADR   = 4'd2,
    MEMREAD  = 4'd3,
    MEMWB    = 4'd4,
    MEMWRITE = 4'd5,
    EXECUTER = 4'd6,
    ALUWB    = 4'd7,
    EXECUTEI = 4'd8,
    JAL      = 4'd9,
    BEQ      = 4'd10
  } statetype;

  statetype state, nextstate;

  // 1. State Register (Memory Block) - Updates state on clock edge
  always_ff @(posedge clk or posedge reset) begin
    if (reset) state <= FETCH;
    else       state <= nextstate;
  end

  // 2. Next State and Output Logic (Brain Block)
  always_comb begin
    // Default assignments to prevent latches and satisfy the "don't care = 0" rule
    ResultSrc = 2'b00;
    MemWrite  = 1'b0;
    IRWrite   = 1'b0;
    ALUSrcA   = 2'b00;
    ALUSrcB   = 2'b00;
    AdrSrc    = 1'b0;
    PCUpdate  = 1'b0;
    Branch    = 1'b0;
    RegWrite  = 1'b0;
    ALUOp     = 2'b00;
    nextstate = FETCH; // Default next state

    case (state)
      FETCH: begin
        AdrSrc    = 1'b0;
        IRWrite   = 1'b1;
        ALUSrcA   = 2'b00;
        ALUSrcB   = 2'b10;
        ALUOp     = 2'b00;
        ResultSrc = 2'b10;
        PCUpdate  = 1'b1;
        nextstate = DECODE;
      end

      DECODE: begin
        ALUSrcA   = 2'b01;
        ALUSrcB   = 2'b01;
        ALUOp     = 2'b00;
        // Determine the next path based on opcode
        case (op)
          7'b0000011: nextstate = MEMADR;   // lw
          7'b0100011: nextstate = MEMADR;   // sw
          7'b0110011: nextstate = EXECUTER; // R-type
          7'b0010011: nextstate = EXECUTEI; // I-type ALU
          7'b1101111: nextstate = JAL;      // jal
          7'b1100011: nextstate = BEQ;      // beq
          default:    nextstate = FETCH;
        endcase
      end

      MEMADR: begin
        ALUSrcA   = 2'b10;
        ALUSrcB   = 2'b01;
        ALUOp     = 2'b00;
        if (op == 7'b0000011) nextstate = MEMREAD; // lw path
        else                  nextstate = MEMWRITE; // sw path
      end

      MEMREAD: begin
        ResultSrc = 2'b00;
        AdrSrc    = 1'b1;
        nextstate = MEMWB;
      end

      MEMWB: begin
        ResultSrc = 2'b01;
        RegWrite  = 1'b1;
        nextstate = FETCH; // Instruction complete, fetch next
      end

      MEMWRITE: begin
        ResultSrc = 2'b00;
        AdrSrc    = 1'b1;
        MemWrite  = 1'b1;
        nextstate = FETCH; // Instruction complete, fetch next
      end

      EXECUTER: begin
        ALUSrcA   = 2'b10;
        ALUSrcB   = 2'b00;
        ALUOp     = 2'b10;
        nextstate = ALUWB;
      end

      ALUWB: begin
        ResultSrc = 2'b00;
        RegWrite  = 1'b1;
        nextstate = FETCH; // Instruction complete, fetch next
      end

      EXECUTEI: begin
        ALUSrcA   = 2'b10;
        ALUSrcB   = 2'b01;
        ALUOp     = 2'b10;
        nextstate = ALUWB;
      end

      JAL: begin
        ALUSrcA   = 2'b01;
        ALUSrcB   = 2'b10;
        ALUOp     = 2'b00;
        ResultSrc = 2'b00;
        PCUpdate  = 1'b1;
        nextstate = ALUWB;
      end

      BEQ: begin
        ALUSrcA   = 2'b10;
        ALUSrcB   = 2'b00;
        ALUOp     = 2'b01;
        ResultSrc = 2'b00;
        Branch    = 1'b1;
        nextstate = FETCH; // Instruction complete, fetch next
      end

      default: nextstate = FETCH;
    endcase
  end

endmodule
