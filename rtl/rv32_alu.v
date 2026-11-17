// rv32_alu.v - RV32I integer ALU
// alu_ctrl = {alt, funct3}; alt selects SUB (funct3=000) or SRA (funct3=101)
module rv32_alu (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [3:0]  alu_ctrl,
    output reg  [31:0] y
);
    wire        alt    = alu_ctrl[3];
    wire [2:0]  f3     = alu_ctrl[2:0];
    wire [4:0]  shamt  = b[4:0];

    // Keep the arithmetic shift in its own signed expression. Inside a ?: with
    // an unsigned operand, Verilog would evaluate >>> as a logical shift.
    wire signed [31:0] a_s = a;
    wire        [31:0] sra = a_s >>> shamt;

    always @(*) begin
        case (f3)
            3'b000: y = alt ? (a - b) : (a + b);                    // ADD/SUB
            3'b001: y = a << shamt;                                  // SLL
            3'b010: y = {31'd0, $signed(a) < $signed(b)};            // SLT
            3'b011: y = {31'd0, a < b};                              // SLTU
            3'b100: y = a ^ b;                                       // XOR
            3'b101: y = alt ? sra : (a >> shamt); // SRA/SRL
            3'b110: y = a | b;                                       // OR
            default: y = a & b;                                      // AND
        endcase
    end
endmodule
