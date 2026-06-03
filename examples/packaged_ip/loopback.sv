// Trivial HDL body shipped inside the packaged IP tree. Real IPs
// would ship a functional module here plus supporting XDC + Tcl.
module loopback(input logic a, output logic b);
    assign b = a;
endmodule
