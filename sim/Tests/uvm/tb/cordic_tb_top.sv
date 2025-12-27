module cordic_tb_top;

    timeunit 1ns;
    timeprecision 100ps;

    import uvm_pkg::*;
    import cordic_tb_pkg::*;
    import cordic_pkg::*;
    `include "uvm_macros.svh"
    import cordic_test_pkg::*;
    import cordic_seq_pkg::*;
    import cordic_agent_pkg::*;
    import cordic_env_pkg::*;

    logic clk;
    initial clk = 1'b0;
    always #5 clk = ~clk;

    cordic_cfg cfg;

    cordic_if #(.XY_W(16), .ANGLE_W(32)) vif (.clk(clk));

    localparam int MODE = 0; // 0: rotation, 1: vectoring
    localparam int GAIN_COMP = 1

    cordic_dut_uvm #(
        .MODE(MODE),
        .GAIN_COMP(GAIN_COMP)
    ) dut (
        .clk(clk),
        .rst_n(vif.rst_n),
        .in_valid(vif.in_valid),
        .in_ready(vif.in_ready),
        .x_in(vif.x_in),
        .y_in(vif.y_in),
        .z_in(vif.z_in),
        .out_valid(vif.out_valid),
        .out_ready(vif.out_ready),
        .cos_out(vif.cos_out),
        .sin_out(vif.sin_out),
        .mag_out(vif.mag_out),
        .theta_out(vif.theta_out)
    );

    initial begin
        vif.rst_n = 1'b0;
        vif.in_valid = 1'b0;
        vif.x_in = '0;
        vif.y_in = '0;
        vif.z_in = '0;
        vif.out_ready = 1'b1;

        repeat (5) @(posedge clk);
        vif.rst_n = 1'b1;
    end

    initial begin
        $shm_open("waves.shm");
        $shm_probe("AS");

        uvm_config_db#(virtual cordic_if.drv)::set(null, "*drv*", "vif", vif);
        uvm_config_db#(virtual cordic_if.mon)::set(null, "*mon*", "vif", vif);

        cfg = cordic_cfg::type_id::create("cfg");
        cfg.mode = (MODE == 0) ? CORDIC_ROT : CORDIC_VEC;
        cfg.gain_comp = GAIN_COMP;
        cfg.tol_xy_lsb = 10; // adjust as needed for tolerance (accumulated error due to quantization)
        cfg.tol_theta_lsb = 600000; // adjust as needed for tolerance (off by ~0.09 degrees)
        uvm_config_db #(cordic_cfg)::set(uvm_root::get(), "*", "cfg", cfg);
        
        run_test();
    end

endmodule : cordic_tb_top
