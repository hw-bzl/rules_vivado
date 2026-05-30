"""Resource set definitions for Vivado actions.

Vivado's `general.maxThreads` property caps at 32 on Linux (8 on Windows) for
the multi-threaded commands (`synth_design`, `opt_design`, `place_design`,
`phys_opt_design`, `route_design`). Asking for more is silently clamped, so we
only enumerate `cpu_1` .. `cpu_32`. `get_resource_set` saturates above that.
"""

MAX_VIVADO_THREADS = 32

def _resource_set_cpu_1(_os_name, _inputs):
    return {"cpu": 1}

def _resource_set_cpu_2(_os_name, _inputs):
    return {"cpu": 2}

def _resource_set_cpu_3(_os_name, _inputs):
    return {"cpu": 3}

def _resource_set_cpu_4(_os_name, _inputs):
    return {"cpu": 4}

def _resource_set_cpu_5(_os_name, _inputs):
    return {"cpu": 5}

def _resource_set_cpu_6(_os_name, _inputs):
    return {"cpu": 6}

def _resource_set_cpu_7(_os_name, _inputs):
    return {"cpu": 7}

def _resource_set_cpu_8(_os_name, _inputs):
    return {"cpu": 8}

def _resource_set_cpu_9(_os_name, _inputs):
    return {"cpu": 9}

def _resource_set_cpu_10(_os_name, _inputs):
    return {"cpu": 10}

def _resource_set_cpu_11(_os_name, _inputs):
    return {"cpu": 11}

def _resource_set_cpu_12(_os_name, _inputs):
    return {"cpu": 12}

def _resource_set_cpu_13(_os_name, _inputs):
    return {"cpu": 13}

def _resource_set_cpu_14(_os_name, _inputs):
    return {"cpu": 14}

def _resource_set_cpu_15(_os_name, _inputs):
    return {"cpu": 15}

def _resource_set_cpu_16(_os_name, _inputs):
    return {"cpu": 16}

def _resource_set_cpu_17(_os_name, _inputs):
    return {"cpu": 17}

def _resource_set_cpu_18(_os_name, _inputs):
    return {"cpu": 18}

def _resource_set_cpu_19(_os_name, _inputs):
    return {"cpu": 19}

def _resource_set_cpu_20(_os_name, _inputs):
    return {"cpu": 20}

def _resource_set_cpu_21(_os_name, _inputs):
    return {"cpu": 21}

def _resource_set_cpu_22(_os_name, _inputs):
    return {"cpu": 22}

def _resource_set_cpu_23(_os_name, _inputs):
    return {"cpu": 23}

def _resource_set_cpu_24(_os_name, _inputs):
    return {"cpu": 24}

def _resource_set_cpu_25(_os_name, _inputs):
    return {"cpu": 25}

def _resource_set_cpu_26(_os_name, _inputs):
    return {"cpu": 26}

def _resource_set_cpu_27(_os_name, _inputs):
    return {"cpu": 27}

def _resource_set_cpu_28(_os_name, _inputs):
    return {"cpu": 28}

def _resource_set_cpu_29(_os_name, _inputs):
    return {"cpu": 29}

def _resource_set_cpu_30(_os_name, _inputs):
    return {"cpu": 30}

def _resource_set_cpu_31(_os_name, _inputs):
    return {"cpu": 31}

def _resource_set_cpu_32(_os_name, _inputs):
    return {"cpu": 32}

_RESOURCE_SETS = {
    1: _resource_set_cpu_1,
    2: _resource_set_cpu_2,
    3: _resource_set_cpu_3,
    4: _resource_set_cpu_4,
    5: _resource_set_cpu_5,
    6: _resource_set_cpu_6,
    7: _resource_set_cpu_7,
    8: _resource_set_cpu_8,
    9: _resource_set_cpu_9,
    10: _resource_set_cpu_10,
    11: _resource_set_cpu_11,
    12: _resource_set_cpu_12,
    13: _resource_set_cpu_13,
    14: _resource_set_cpu_14,
    15: _resource_set_cpu_15,
    16: _resource_set_cpu_16,
    17: _resource_set_cpu_17,
    18: _resource_set_cpu_18,
    19: _resource_set_cpu_19,
    20: _resource_set_cpu_20,
    21: _resource_set_cpu_21,
    22: _resource_set_cpu_22,
    23: _resource_set_cpu_23,
    24: _resource_set_cpu_24,
    25: _resource_set_cpu_25,
    26: _resource_set_cpu_26,
    27: _resource_set_cpu_27,
    28: _resource_set_cpu_28,
    29: _resource_set_cpu_29,
    30: _resource_set_cpu_30,
    31: _resource_set_cpu_31,
    32: _resource_set_cpu_32,
}

def get_resource_set(jobs):
    """Get the `ctx.actions.run.resource_set` for the Vivado actions.

    Args:
        jobs (int): The number of jobs the action is expected to consume.
            Values above MAX_VIVADO_THREADS are clamped (Vivado will not use
            more threads than that even if asked).

    Returns:
        Optional[Callable]: A resource set appropriate for the current configuration.
    """

    if jobs > MAX_VIVADO_THREADS:
        return _RESOURCE_SETS[MAX_VIVADO_THREADS]

    return _RESOURCE_SETS[jobs]
