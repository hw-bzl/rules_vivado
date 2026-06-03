# Block-design helpers shared across designs. Real ones wrap the
# `create_bd_cell` boilerplate for a vendor IP; this one just names the
# design so the example stays buildable in seconds.
package provide bd_helpers 1.0

namespace eval bd_helpers {
    proc create_named_design {name} {
        create_bd_design $name
    }
}
