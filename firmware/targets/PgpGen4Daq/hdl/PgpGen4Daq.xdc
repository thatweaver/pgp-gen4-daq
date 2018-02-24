set_clock_groups -asynchronous \
                 -group [get_clocks -include_generated_clocks {ddrClkP0}] \
                 -group [get_clocks -include_generated_clocks {pciRefClkP}] \
                 -group [get_clocks -include_generated_clocks {pciExtRefClkP}]
set_clock_groups -asynchronous \
                 -group [get_clocks -include_generated_clocks {ddrClkP1}] \
                 -group [get_clocks -include_generated_clocks {pciRefClkP}] \
                 -group [get_clocks -include_generated_clocks {pciExtRefClkP}]
set_clock_groups -asynchronous \
                 -group [get_clocks -include_generated_clocks {ddrClkP2}] \
                 -group [get_clocks -include_generated_clocks {pciRefClkP}] \
                 -group [get_clocks -include_generated_clocks {pciExtRefClkP}]
set_clock_groups -asynchronous \
                 -group [get_clocks -include_generated_clocks {ddrClkP3}] \
                 -group [get_clocks -include_generated_clocks {pciRefClkP}] \
                 -group [get_clocks -include_generated_clocks {pciExtRefClkP}]

set_clock_groups -asynchronous \
                 -group [get_clocks -include_generated_clocks {ddrClkP0}] \
                 -group [get_clocks -include_generated_clocks {qsfp0RefClkP0}]

set_clock_groups -asynchronous \
                 -group [get_clocks -include_generated_clocks {ddrClkP1}] \
                 -group [get_clocks -include_generated_clocks {qsfp0RefClkP0}]

set_clock_groups -asynchronous \
                 -group [get_clocks -include_generated_clocks {ddrClkP2}] \
                 -group [get_clocks -include_generated_clocks {qsfp1RefClkP0}]

set_clock_groups -asynchronous \
                 -group [get_clocks -include_generated_clocks {ddrClkP3}] \
                 -group [get_clocks -include_generated_clocks {qsfp1RefClkP0}]

