// Source for the `vivado_interface_definition` instance.
interface pulse_if;
    logic valid;
    logic ready;

    modport master(output valid, input ready);
    modport slave(input valid, output ready);
endinterface
