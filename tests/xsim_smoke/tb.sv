// Smallest possible xsim smoke test — 10 posedges + one assertion +
// 10 more posedges + $finish. Total sim time ~200ns, comfortably
// inside xsim's default 1000ns `run` window (the exported
// `<top>.sh` doesn't customize `xsim.simulate.runtime`).
module xsim_smoke_tb ();

  logic clk = 0;
  always #5ns clk = !clk;

  initial begin
    repeat (10) @(posedge clk);
    assert (1)
    else $error("A message about failed assertion");
    repeat (10) @(posedge clk);
    $finish();
  end

endmodule
