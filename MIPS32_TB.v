

`timescale 1ns / 1ps

module MIPS32_TB;
    reg clk1, clk2, reset;
    integer i;

    // Instantiate the MIPS32 module
    MIPS32 uut (
        .clk1(clk1),
        .clk2(clk2),
        .reset(reset)
    );

    // Generate Clock Signals
    always #5 clk1 = ~clk1;  // Clock with period of 10 ns
    always #5 clk2 = ~clk2;  // Clock with period of 10 ns, shifted by 5 ns

    initial begin
        // Initialize Inputs
        clk1 = 0; clk2 = 0; reset = 1;

        // Wait for some cycles before deasserting reset
        #10 reset = 0;  

        // Initialize Registers and Cache
        uut.init_registers;
        uut.init_cache;

        // Initialize Memory with Instructions (Manually or using a Memory File)
        // Example Program:
        // ADD  R4, R1, R3    -> R4 = R1 + R3   (5)
        // SUB  R5, R4, R2    -> R5 = R4 - R2   (X)
        // ADDI R6, R6, 1     -> R6 = R6 + 1    (7)
        uut.Mem[0] = {6'b000000, 5'b00001, 5'b00011, 5'b00100, 5'b00000, 6'b000000};  // ADD R4, R1, R3
        uut.Mem[1] = {6'b000001, 5'b00100, 5'b00010, 5'b00101, 5'b00000, 6'b000001};  // SUB R5, R4, R2
        uut.Mem[2] = {6'b001010, 5'b00110, 5'b00110, 16'b0000000000000001};           // ADDI R6, R6, 1
        uut.Mem[3] = {6'b111111, 26'b0};  // HALT instruction

        // Run Simulation for a Fixed Duration
        #100;
        
        // Display Register Values
        $display("\nFinal Register Values:");
        for (i = 0; i < 8; i = i + 1)
            $display("R[%0d] = %0d", i, uut.Reg[i]);

        // End Simulation
        $stop;
    end
  initial begin // Required to dump signals to EPWave      
    $dumpfile("dump.vcd"); 
    $dumpvars(0);
  end
endmodule
