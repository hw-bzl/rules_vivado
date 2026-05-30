"""Convenience macro chaining the full Vivado bitstream flow."""

load(":bitstream.bzl", "vivado_write_bitstream")
load(":implementation.bzl", "vivado_place_optimize", "vivado_placement", "vivado_routing")
load(":synthesis.bzl", "vivado_synthesis_optimize", "vivado_synthesize")

def vivado_flow(
        *,
        name,
        module,
        module_top,
        part_number,
        tags = [],
        ip_blocks = [],
        with_xsa = False,
        **kwargs):
    """Runs the entire bitstream flow as a convenience macro.

    Args:
        name: The name to use when calling the rules.
        module: The verilog library to use as the top level.
        module_top: The name of the top level module.
        part_number: The part number to target.
        tags: Optional tags to use for the rules.
        ip_blocks: Optional ip blocks to include in a design.
        with_xsa: Also generate the xsa file.
        **kwargs: Additional keyword arguments
    """
    vivado_synthesize(
        name = "{}_synth".format(name),
        module = module,
        module_top = module_top,
        part_number = part_number,
        tags = tags,
        ip_blocks = ip_blocks,
        **kwargs
    )

    vivado_synthesis_optimize(
        name = "{}_synth_opt".format(name),
        checkpoint = ":{}_synth".format(name),
        tags = tags,
        **kwargs
    )

    vivado_placement(
        name = "{}_placement".format(name),
        checkpoint = "{}_synth_opt".format(name),
        tags = tags,
        **kwargs
    )

    vivado_place_optimize(
        name = "{}_place_opt".format(name),
        checkpoint = "{}_placement".format(name),
        tags = tags,
        **kwargs
    )

    vivado_routing(
        name = "{}_route".format(name),
        checkpoint = "{}_place_opt".format(name),
        tags = tags,
        **kwargs
    )

    vivado_write_bitstream(
        name = name,
        checkpoint = "{}_route".format(name),
        tags = tags,
        with_xsa = with_xsa,
        **kwargs
    )
