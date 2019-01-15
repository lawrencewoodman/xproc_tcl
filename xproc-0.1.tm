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

  uplevel 1 [list proc $commandName $commandArgs $commandBody]

  if {[info exists options(description)]} {
    uplevel 1 [list xproc::describe $commandName $options(description)]
  }

  if {[info exists options(test)]} {
    uplevel 1 [list xproc::test $commandName $options(test)]
  }
}


proc xproc::remove {type args} {
  variable tests
  variable descriptions
  switch $type {
    tests {
      set tests [
        dict filter $tests script {commandName test} {
          set keep true
          set ns [namespace qualifier $commandName]
          if {$ns eq ""} {set ns "::"}
          foreach nsPattern $args {
            if {[string match $nsPattern $ns]} {
              set keep false
              break
            }
          }
          set keep
        }
      ]
    }
    descriptions {
      set descriptions [
        dict filter $descriptions script {commandName description} {
          set keep true
          set ns [namespace qualifier $commandName]
          if {$ns eq ""} {set ns "::"}
          foreach nsPattern $args {
            if {[string match $nsPattern $ns]} {
              set keep false
            }
          }
          set keep
        }
      ]
    }
    default {
      return -code error "invalid type: $type"
    }
  }
}


proc xproc::test {commandName lambda} {
  variable tests
  set fullCommandName [
    uplevel 1 [list namespace which -command $commandName]
  ]
  dict set tests $fullCommandName [dict create lambda $lambda fail false]
}


proc xproc::describe {commandName description} {
  variable descriptions
  set fullCommandName [
    uplevel 1 [list namespace which -command $commandName]
  ]
  dict set descriptions $fullCommandName [TidyDescription $description]
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
      set lambda [dict get $test lambda]
      uplevel 1 [list apply $lambda $commandName]
    } on error {result returnOptions} {
      set errorInfo [dict get $returnOptions -errorinfo]
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
  set summary [MakeSummary $tests]
  dict with summary {
    puts "\nTotal: $total,  Passed: $passed,  Failed: $failed"
  }
  return $numFail
}


proc xproc::testFail {commandName msg} {
  variable tests
  dict set tests $commandName fail true
  puts "--- FAIL  $commandName"
  puts "---       $msg"
}


# TODO: Add a way of testing against returnCodes and matchType, etc
proc xproc::testCases {testState cases lambdaExpr} {
  set i 0
  foreach case $cases {
    dict with case {
      set got [uplevel 1 [list apply $lambdaExpr $input]]
      if {$got ne $want} {
        xproc::testFail $testState "($i) got: $got, want: $want"
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


xproc::proc xproc::MakeSummary {tests} {
  set total [llength [dict keys $tests]]
  set failed 0
  dict for {commandName test} $tests {
    if {[dict get $test fail]} {incr failed}
  }
  set passed [expr {$total-$failed}]
  return [dict create total $total passed $passed failed $failed]
} -test {{t} {
  set cases [list \
    [dict create input {} \
     want [dict create total 0 passed 0 failed 0]] \
    [dict create input {name-1 {fail true}} \
     want [dict create total 1 passed 0 failed 1]] \
    [dict create input {name-1 {fail false}} \
     want [dict create total 1 passed 1 failed 0]] \
    [dict create input {name-1 {fail false} name-2 {fail false}} \
     want [dict create total 2 passed 2 failed 0]] \
    [dict create input {name-1 {fail true} name-2 {fail false}} \
     want [dict create total 2 passed 1 failed 1]] \
    [dict create input {name-1 {fail false} name-2 {fail true}} \
     want [dict create total 2 passed 1 failed 1]] \
    [dict create input {name-1 {fail true} name-2 {fail true}} \
     want [dict create total 2 passed 0 failed 2]] \
  ]
  xproc::testCases $t $cases {{input} {xproc::MakeSummary $input}}
}}


xproc::proc xproc::IndentEachLine {text numSpaces ignoreLines} {
  set lines [split $text "\n"]
  set i 0
  foreach line $lines {
    if {$i < $ignoreLines || $line eq ""} {
      lappend indentedLines $line
    } else {

      lappend indentedLines "[string repeat " " $numSpaces]$line"
    }
    incr i
  }
  return [join $indentedLines "\n"]
} -test {{t} {
  set text {this is some text
and a little more

and some more here
    this has some more
 and a little less indented}
  set want {this is some text
          and a little more

          and some more here
              this has some more
           and a little less indented}
  set got [xproc::IndentEachLine $text 10 1]
  if {$got ne $want} {
    xproc::testFail $t "got: $got, want: $want"
  }
}}


xproc::proc xproc::CountIndent {line} {
  set count 0
  for {set i 0} {$i < [string length $line]} {incr i} {
    if {[string index $line $i] eq " "} {
      incr count
    } else {
      break
    }
  }
  return $count
} -test {{t} {
  set cases {
    {input {hello this is some text} want 0}
    {input {  hello this is some text} want 2}
    {input {  hello this is some text   } want 2}
    {input {    hello this is some text } want 4}
  }
  xproc::testCases $t $cases {{input} {xproc::CountIndent $input}}
}}


xproc::proc xproc::StripIndent {lines numSpaces} {
  set newLines [list]
  foreach line $lines {
    for {set i 0} {$i < [string length $line] && $i < $numSpaces} {incr i} {
      if {[string index $line $i] ne " "} {break}
    }
    lappend newLines [string range $line $i end]
  }
  return $newLines
} -test {{t} {
  set cases {
    {input {
      { "hello some text"
        " some more text"
        "and a little more"
        "   guess what"
      } 0} want {
        "hello some text"
        " some more text"
        "and a little more"
        "   guess what"
      }}
    {input {
      { "hello some text"
        " some more text"
        "and a little more"
        "   guess what"
      } 1} want {
        "hello some text"
        "some more text"
        "and a little more"
        "  guess what"
      }}
    {input {
      { "hello some text"
        " some more text"
        "and a little more"
        "   guess what"
      } 2} want {
        "hello some text"
        "some more text"
        "and a little more"
        " guess what"
      }}
    {input {
      { "hello some text"
        " some more text"
        "and a little more"
        "   guess what"
      } 3} want {
        "hello some text"
        "some more text"
        "and a little more"
        "guess what"
      }}
  }
  set i 0
  foreach c $cases {
    dict with c {
      set got [xproc::StripIndent {*}$input]
      if {[llength $got] != [llength $want]} {
        xproc::testFail $t "($i) got: $got, want: $want"
      } else {
        foreach g $got w $want {
          if {$g ne $w} {
            xproc::testFail $t "($i) got: $got, want: $want"
            break
          }
        }
      }
    }
    incr i
  }
}}


xproc::proc xproc::TidyDescription {description} {
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
} -test {{t} {
  set cases {
    { input {this is a description}
      want {this is a description}}
    { input {
        this is a description
      }
      want {this is a description}}
    { input {
        this is a description

        this is some more text on another
        line to see if everything is aligned properly
          this text is indent further

          as is this line
            even futher down here
      }
      want {this is a description

this is some more text on another
line to see if everything is aligned properly
  this text is indent further

  as is this line
    even futher down here}}
    { input {this is a description without a leading newline

        this is some more text on another
        line to see if everything is aligned properly
      }
      want {this is a description without a leading newline

        this is some more text on another
        line to see if everything is aligned properly}}
  }

  xproc::testCases $t $cases {{input} {xproc::TidyDescription $input}}
}}
