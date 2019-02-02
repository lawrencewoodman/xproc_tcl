######################################
# Output the descriptions for xproc
######################################

# Add module dir to tm paths
set ThisScriptDir [file dirname [info script]]
set ModuleDir [file normalize [file join $ThisScriptDir ..]]
::tcl::tm::path add $ModuleDir

package require xproc

proc compareDescriptions {a b} {
  string compare [dict get $a name] [dict get $b name]
}

set xprocDescriptions [xproc::descriptions -match {::xproc::*}]
set xprocDescriptions [lsort -command compareDescriptions $xprocDescriptions]

foreach desc $xprocDescriptions {
  dict with desc {
    puts $name
    puts "[string repeat "=" [string length $name]]\n"
    puts $description
    puts "\n\n"
  }
}
