# An extended proc implementation
#
# Copyright (C) 2019 Lawrence Woodman <lwoodman@vlifesystems.com>
# Licensed under an MIT licence.  Please see LICENCE.md for details.

package require Tcl 8.6

namespace eval xproc {
  namespace export {[a-z]*}
  variable tests [dict create]
  variable descriptions [dict create]
}


proc xproc::proc {commandName commandArgs commandBody args} {
  variable tests
  variable descriptions
  array set options {}
  while {[llength $args]} {
    switch -glob -- [lindex $args 0] {
      -desc* {set args [lassign $args - options(description)]}
      -test {set args [lassign $args - options(test)]}
      --      {set args [lrange $args 1 end] ; break}
      -*      {error "unknown option [lindex $args 0]"}
      default break
    }
    # TODO: Check error above
  }

  if {[info exists options(description)]} {
    dict set descriptions $commandName [TidyDescription $options(description)]
  }

  if {[info exists options(test)]} {
    # TODO: Ensure works within namespace eval, so perhaps need to get
    # TODO: namespace and prepend commandName with that
    dict set tests $commandName [
      dict create lambda $options(test) fail false
    ]
  }

  # TODO: Is uplevel needed here?
  uplevel 1 [list proc $commandName $commandArgs $commandBody]
}


# TODO: Add a -match switch
# TODO: Add -silent switch
proc xproc::runTests {args} {
  variable tests

  array set options {verbose 0}
  while {[llength $args]} {
    switch -glob -- [lindex $args 0] {
      -verbose {set options(verbose) 1 ; set args [lrange $args 1 end]}
      --      {set args [lrange $args 1 end] ; break}
      -*      {error "unknown option [lindex $args 0]"}
      default break
    }
  }
  if {[llength $args] > 0} {
    return -code error "invalid number of arguments"
  }

  set numFail 0
  dict for {commandName test} $tests {
    if {$options(verbose)} {
      puts "=== RUN   $commandName"
    }
    try {
      uplevel 1 [list apply [dict get $test lambda] $commandName]
    } on error {result returnOptions} {
      set errorInfo [dict get $returnOptions -errorinfo]
      set errorInfo [join [lrange [split $errorInfo "\n"] 0 5] "\n"]
      puts "--- FAIL  $commandName"
      puts "---       [IndentEachLine $errorInfo 10 1]"
      dict set tests $commandName fail true
    }
    if {[dict get $tests $commandName fail]} {
      incr numFail
    } else {
      if {$options(verbose)} {
        puts "--- PASS  $commandName"
      }
      # TODO: time test
    }
  }
  PrintSummary $tests
  return $numFail
}

proc xproc::testError {commandName msg} {
  variable tests
  dict set tests $commandName fail true
  puts "--- FAIL  $commandName"
  puts "---       $msg"
}

proc xproc::testFatal {commandName msg} {
  return -code error $msg
}

# TODO: Add a way of testing against returnCodes and matchType, etc
proc xproc::testCases {testState cases lambdaExpr} {
  set i 0
  foreach case $cases {
    dict with case {
      set got [uplevel 1 [list apply $lambdaExpr $input]]
      if {$got ne $want} {
        xproc::testError $testState "($i) got: $got, want: $want"
      }
    }
    incr i
  }
}

# TODO: Add a -match switch
proc xproc::descriptions {} {
  variable descriptions
  return $descriptions
}

proc xproc::PrintSummary {tests} {
  set total [llength [dict keys $tests]]
  set failed 0
  dict for {commandName test} $tests {
    if {[dict get $test fail]} {incr failed}
  }
  set passed [expr {$total-$failed}]
  puts "\nTotal:  $total,  Passed:   $passed,   Failed:   $failed"
}

proc xproc::IndentEachLine {text numSpaces ignoreLines} {
  set lines [split $text "\n"]
  set i 0
  foreach line $lines {
    if {$i < $ignoreLines} {
      lappend indentedLines $line
    } else {
      lappend indentedLines "[string repeat " " $numSpaces]$line"
    }
    incr i
  }
  return [join $indentedLines "\n"]
}

proc xproc::CountIndent {line} {
  set count 0
  for {set i 0} {$i < [string length $line]} {incr i} {
    if {[string index $line $i] eq " "} {
      incr count
    } else {
      break
    }
  }
  return $count
}

proc xproc::StripIndent {lines numSpaces} {
  set newLines [list]
  foreach line $lines {
    for {set i 0} {$i < [string length $line] && $i < $numSpaces} {incr i} {
      if {[string index $line $i] ne " "} {break}
    }
    lappend newLines [string range $line $i end]
  }
  return $newLines
}

proc xproc::TidyDescription {description} {
  set description [string trimright $description]
  set lines [split $description "\n"]

  # Strip first newlines
  set lineNum 0
  foreach line $lines {
    if {[string trim $line] ne ""} {break}
    incr lineNum
  }
  set lines [lrange $lines $lineNum end]
  set normalIndent [CountIndent [lindex $lines 0]]
  set lines [StripIndent $lines $normalIndent]
  return [join $lines "\n"]
}
