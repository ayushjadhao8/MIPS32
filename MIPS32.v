// Code your design here
`timescale 1ns / 1ps

module MIPS32(clk1, clk2, reset);

input clk1, clk2, reset;

reg [31:0] PC, IF_ID_IR, IF_ID_NPC;
reg [31:0] ID_EX_IR, ID_EX_NPC, ID_EX_A, ID_EX_B, ID_EX_Imm;
reg [31:0] EX_MEM_IR, EX_MEM_ALUOUT, EX_MEM_B;
reg [31:0] MEM_WB_IR, MEM_WB_ALUOUT, MEM_WB_LMD;

reg [2:0] ID_EX_type, EX_MEM_type, MEM_WB_type;
reg EX_MEM_cond;

reg [31:0] Reg [31:0];    // Register Bank (32 * 32)
reg [31:0] Mem [1023:0];  // Main Memory (1024 * 32)

// Cache Memory
reg [31:0] L1_Cache [15:0]; // L1 Cache (16 blocks)
reg [31:0] L2_Cache [31:0]; // L2 Cache (32 blocks)
reg [3:0] L1_Tags [15:0];   // L1 Cache Tags
reg [4:0] L2_Tags [31:0];   // L2 Cache Tags
reg L1_Valid [15:0];        // L1 Valid Bits
reg L2_Valid [31:0];        // L2 Valid Bits

parameter ADD=6'b000000, SUB=6'b000001, AND=6'b000010, OR=6'b000011, SLT=6'b000100, MUL=6'b000101, HLT=6'b111111,
          LW=6'b001000, SW=6'b001001, ADDI=6'b001010, SUBI=6'b001011, SLTI=6'b001100, BNEQZ=6'b001101, BEQZ=6'b001110;
          
parameter RR_ALU=3'b000, RM_ALU=3'b001, LOAD=3'b010, STORE=3'b011, BRANCH=3'b100, HALT=3'b101;

reg HALTED;  // Set after HLT instruction is completed
reg TAKEN_BRANCH;  // Used to disable instructions after a branch

// Initialization
initial begin
    PC = 0;
    HALTED = 0;
end

task init_registers;
    integer i;
    begin
        for (i = 0; i < 32; i = i + 1)
            Reg[i] = i;
    end
endtask

task init_cache;
    integer i;
    begin
        for (i = 0; i < 16; i = i + 1) begin
            L1_Cache[i] = 32'b0;
            L1_Tags[i] = 4'b0;
            L1_Valid[i] = 0;
        end
        for (i = 0; i < 32; i = i + 1) begin
            L2_Cache[i] = 32'b0;
            L2_Tags[i] = 5'b0;
            L2_Valid[i] = 0;
        end
    end
endtask

// Cache Read Function
function [31:0] cache_read;
    input [31:0] addr;
    integer index;
    begin
        index = addr[3:0]; // Correct L1 Cache Index
        if (L1_Valid[index] && (L1_Tags[index] == addr[31:4])) begin
            cache_read = L1_Cache[index]; // L1 Cache Hit
        end else begin
            index = addr[4:0]; // Correct L2 Cache Index
            if (L2_Valid[index] && (L2_Tags[index] == addr[31:5])) begin
                cache_read = L2_Cache[index]; // L2 Cache Hit
                // Move to L1
                L1_Cache[addr[3:0]] = L2_Cache[index];
                L1_Tags[addr[3:0]] = addr[31:4];
                L1_Valid[addr[3:0]] = 1;
            end else begin
                cache_read = Mem[addr >> 2]; // Read from Main Memory
                // Move to L2
                L2_Cache[addr[4:0]] = Mem[addr >> 2];
                L2_Tags[addr[4:0]] = addr[31:5];
                L2_Valid[addr[4:0]] = 1;
            end
        end
    end
endfunction

// ✅ Corrected Cache Write Task
task cache_write;
    input [31:0] addr, data;
    integer index;
    begin
        index = addr[3:0]; // L1 Cache Index
        if (L1_Valid[index] && (L1_Tags[index] == addr[31:4])) begin
            L1_Cache[index] = data; // L1 Cache Write
            L2_Cache[addr[4:0]] = data; // Write-through to L2
        end
        index = addr[4:0]; // L2 Cache Index
        if (L2_Valid[index] && (L2_Tags[index] == addr[31:5])) begin
            L2_Cache[index] = data; // L2 Cache Write
        end
        Mem[addr >> 2] = data; // Always write to Main Memory
    end
endtask




// Instruction Fetch (IF)
always @(posedge clk1) 
if (HALTED == 0) begin    
    if (TAKEN_BRANCH)
        PC <= #2 PC;  // ✅ Stop fetching when branch is taken
    else begin
        IF_ID_IR  <= #2 cache_read(PC);
        IF_ID_NPC <= #2 PC + 1;
        PC        <= #2 PC + 1;
    end
end


// Instruction Decode (ID)
always @(posedge clk2) 
if (HALTED == 0) begin
    // Read register values (Register file read)
    ID_EX_A <= (IF_ID_IR[25:21] == 5'b00000) ? 0 : Reg[IF_ID_IR[25:21]];
    ID_EX_B <= (IF_ID_IR[20:16] == 5'b00000) ? 0 : Reg[IF_ID_IR[20:16]];
    
    // Pass PC and instruction to the next stage
    ID_EX_NPC <= #2 IF_ID_NPC;
    ID_EX_IR  <= #2 IF_ID_IR;
    
    // Sign-extend immediate value (for I-type instructions)
    ID_EX_Imm <= #2 { {16{IF_ID_IR[15]}}, IF_ID_IR[15:0] };  

    // Identify instruction type
    case (IF_ID_IR[31:26])
        ADD, SUB, MUL, AND, OR, SLT: ID_EX_type <= RR_ALU;    // Register-to-Register ALU operations
        ADDI, SUBI, SLTI:            ID_EX_type <= RM_ALU;    // Register-to-Memory ALU operations
        LW:                          ID_EX_type <= LOAD;      // Load instruction
        SW:                          ID_EX_type <= STORE;     // Store instruction
        BNEQZ, BEQZ:                 ID_EX_type <= BRANCH;    // Branch instructions
        HLT:                         ID_EX_type <= HALT;      // Halt instruction
        default:                      ID_EX_type <= 3'b000;   // Default case (avoid X states)
    endcase
end


// Execution (EX)
always @(posedge clk1) 
if (HALTED == 0) begin
    EX_MEM_IR   <= #2 ID_EX_IR;      // Pass instruction to the next stage
    EX_MEM_type <= #2 ID_EX_type;    // Pass type to the next stage
    EX_MEM_B    <= #2 ID_EX_B;       // Forward B register for store operations

    case(ID_EX_type)
       RR_ALU: begin
           case(ID_EX_IR[31:26])
               ADD: EX_MEM_ALUOUT <= #2 ID_EX_A + ID_EX_B;  
               SUB: EX_MEM_ALUOUT <= #2 ID_EX_A - ID_EX_B;
               MUL: EX_MEM_ALUOUT <= #2 ID_EX_A * ID_EX_B;  // Multiplication Handling
               AND: EX_MEM_ALUOUT <= #2 ID_EX_A & ID_EX_B;
               OR:  EX_MEM_ALUOUT <= #2 ID_EX_A | ID_EX_B;
               SLT: EX_MEM_ALUOUT <= #2 (ID_EX_A < ID_EX_B) ? 1 : 0; // Set Less Than
               default: EX_MEM_ALUOUT <= #2 0;  // Avoid X states
           endcase
       end

       LOAD, STORE: begin
           EX_MEM_ALUOUT <= #2 ID_EX_A + ID_EX_Imm;  // Address Calculation
       end
       
       BRANCH: begin
           case(ID_EX_IR[31:26])
               BNEQZ: begin
                   if (ID_EX_A != 0) begin
                       PC <= #2 ID_EX_NPC + ID_EX_Imm;
                       TAKEN_BRANCH <= #2 1; // Mark branch as taken
                   end else TAKEN_BRANCH <= #2 0;
               end
               BEQZ: begin
                   if (ID_EX_A == 0) begin
                       PC <= #2 ID_EX_NPC + ID_EX_Imm;
                       TAKEN_BRANCH <= #2 1; // Mark branch as taken
                   end else TAKEN_BRANCH <= #2 0;
               end
               default: TAKEN_BRANCH <= #2 0; // Default case
           endcase
       end
       
       default: begin
           EX_MEM_ALUOUT <= #2 0;  // Default case to avoid latching
           TAKEN_BRANCH  <= #2 0;
       end
    endcase
end



// Memory Access (MEM)
always @(posedge clk2) 
if (HALTED == 0) begin
    // Pass instruction and type to the next stage
    MEM_WB_IR   <= #2 EX_MEM_IR;
    MEM_WB_type <= #2 EX_MEM_type;

    case (EX_MEM_type)
        LOAD: begin
            MEM_WB_LMD    <= #2 cache_read(EX_MEM_ALUOUT);  // Load from memory
            MEM_WB_ALUOUT <= #2 EX_MEM_ALUOUT;              // Ensure ALU result is passed for WB stage
        end
        STORE: begin
            cache_write(EX_MEM_ALUOUT, EX_MEM_B);  // Store to memory
            MEM_WB_ALUOUT <= #2 EX_MEM_ALUOUT;    // Maintain pipeline consistency
        end
        default: begin
            MEM_WB_ALUOUT <= #2 EX_MEM_ALUOUT;  // Forward ALU result if not a memory operation
        end
    endcase                         
end


// Write Back (WB)
always @(posedge clk1) 
if (HALTED == 0) begin
    case (MEM_WB_type)
        RR_ALU: begin
            if (MEM_WB_IR[15:11] != 5'b00000)  // Prevent writing to register 0
                Reg[MEM_WB_IR[15:11]] <= #2 MEM_WB_ALUOUT;
        end
        LOAD: begin
            if (MEM_WB_IR[20:16] != 5'b00000)  // Prevent writing to register 0
                Reg[MEM_WB_IR[20:16]] <= #2 MEM_WB_LMD;
        end
        HALT: begin
            HALTED <= #2 1'b1;
        end
        default: ; // Do nothing to avoid latches
    endcase
end


endmodule
