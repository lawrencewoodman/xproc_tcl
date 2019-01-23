######################################
# Output the descriptions for xproc
######################################

# Add module dir to tm paths
set ThisScriptDir [file dirname [info script]]
set ModuleDir [file normalize [file join $ThisScriptDir ..]]
::tcl::tm::path add $ModuleDir

package require xproc

set xprocDescriptions [xproc::descriptions -match {::xproc::*}]
set xprocDescriptions [lsort -stride 2 -index 0 $xprocDescriptions]

dict for {procedureName desc} $xprocDescriptions {
  set procedureName [string range $procedureName 2 end]
  puts $procedureName
  puts "[string repeat "=" [string length $procedureName]]\n"
  puts $desc
  puts "\n\n"
}
