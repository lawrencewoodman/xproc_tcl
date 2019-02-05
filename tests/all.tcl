package require Tcl 8.6
package require xproc

set ThisScriptDir [file dirname [info script]]

set summary [
  xproc::runTestFiles -directory [file join $ThisScriptDir main] {*}$argv
]
if {[dict get $summary failed] > 0} {
  exit 1
}
