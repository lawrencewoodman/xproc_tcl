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
      -*      {return -code error "unknown option [lindex $args 0]"}
      default break
    }
  }
  if {[llength $args] > 0} {
    return -code error "invalid number of arguments"
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
  array set options {match {"*"}}
  while {[llength $args]} {
    switch -glob -- [lindex $args 0] {
      -match {set args [lassign $args - options(match)]}
      -*      {return -code error "unknown option [lindex $args 0]"}
      default break
    }
  }
  if {[llength $args] > 0} {
    return -code error "invalid number of arguments"
  }
  set filterLambda {{matchPatterns d} {
    dict filter $d script {commandName -} {
      expr {![MatchCommandName $matchPatterns $commandName]}
    }
  } xproc}
  switch $type {
    tests {set tests [apply $filterLambda $options(match) $tests]}
    descriptions {
      set descriptions [apply $filterLambda $options(match) $descriptions]
    }
    all {
      set tests [apply $filterLambda $options(match) $tests]
      set descriptions [apply $filterLambda $options(match) $descriptions]
    }
    default {return -code error "invalid type: $type"}
  }
}


proc xproc::test {commandName lambda} {
  variable tests
  set fullCommandName [
    uplevel 1 [list namespace which -command $commandName]
  ]
  dict set tests $fullCommandName [dict create lambda $lambda]
}


proc xproc::describe {commandName description} {
  variable descriptions
  set fullCommandName [
    uplevel 1 [list namespace which -command $commandName]
  ]
  dict set descriptions $fullCommandName [TidyDescription $description]
}


proc xproc::runTests {args} {
  variable tests

  array set options {verbose 0 match {"*"}}
  while {[llength $args]} {
    switch -glob -- [lindex $args 0] {
      -match {set args [lassign $args - options(match)]}
      -verbose {set options(verbose) 1 ; set args [lrange $args 1 end]}
      -*      {return -code error "unknown option [lindex $args 0]"}
      default break
    }
  }
  if {[llength $args] > 0} {
    return -code error "invalid number of arguments"
  }

  set numFail 0
  dict for {commandName test} $tests {
    ResetTest $commandName
    if {![MatchCommandName $options(match) $commandName]} {
      dict set tests $commandName skip true
      continue
    }
    if {$options(verbose)} {
      puts "=== RUN   $commandName"
      set timeStart [clock microseconds]
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
        set secondsElapsed [
          expr {([clock microseconds] - $timeStart)/1000000.}
        ]
        puts [format {--- PASS  %s (%0.2fs)} $commandName $secondsElapsed]
      }
    }
  }
  set summary [MakeSummary $tests]
  dict with summary {
    puts "\nTotal: $total,  Passed: $passed,  Skipped: $skipped,  Failed: $failed"
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


xproc::proc xproc::descriptions {args} {
  variable descriptions
  array set options {match {"*"}}
  while {[llength $args]} {
    switch -glob -- [lindex $args 0] {
      -match {set args [lassign $args - options(match)]}
      -*      {return -code error "unknown option [lindex $args 0]"}
      default break
    }
  }
  if {[llength $args] > 0} {
    return -code error "invalid number of arguments"
  }

  dict filter $descriptions script {commandName description} {
    MatchCommandName $options(match) $commandName
  }
}


xproc::proc xproc::MakeSummary {tests} {
  set total [llength [dict keys $tests]]
  set failed 0
  set skipped 0
  dict for {commandName test} $tests {
    if {[dict get $test fail]} {incr failed}
    if {[dict get $test skip]} {incr skipped}
  }
  set passed [expr {($total-$failed)-$skipped}]
  return [dict create \
               total $total passed $passed skipped $skipped failed $failed]
} -test {{t} {
  set cases [list \
    [dict create input {} \
     want [dict create total 0 passed 0 skipped 0 failed 0]] \
    [dict create input {name-1 {skip false fail true}} \
     want [dict create total 1 passed 0 skipped 0 failed 1]] \
    [dict create input {name-1 {skip false fail false}} \
     want [dict create total 1 passed 1 skipped 0 failed 0]] \
    [dict create input {name-1 {skip false fail false} \
                        name-2 {skip false fail false}} \
     want [dict create total 2 passed 2 skipped 0 failed 0]] \
    [dict create input {name-1 {skip false fail true} \
                        name-2 {skip false fail false}} \
     want [dict create total 2 passed 1 skipped 0 failed 1]] \
    [dict create input {name-1 {skip false fail false} \
                        name-2 {skip false fail true}} \
     want [dict create total 2 passed 1 skipped 0 failed 1]] \
    [dict create input {name-1 {skip false fail true} \
                        name-2 {skip false fail true}} \
     want [dict create total 2 passed 0 skipped 0 failed 2]] \
    [dict create input {name-1 {skip true fail false} \
                        name-2 {skip false fail true}} \
     want [dict create total 2 passed 0 skipped 1 failed 1]] \
    [dict create input {name-1 {skip true fail false} \
                        name-2 {skip true fail false}} \
     want [dict create total 2 passed 0 skipped 2 failed 0]] \
  ]
  xproc::testCases $t $cases {{input} {xproc::MakeSummary $input}}
}}


# Does commandName match any of the patterns
xproc::proc xproc::MatchCommandName {matchPatterns commandName} {
  foreach matchPattern $matchPatterns {
    if {[string match $matchPattern $commandName]} {return true}
  }
  return false
} -test {{t} {
  set cases {
    {input {{"*"} someName} want true}
    {input {{"*bob*" "*"} someName} want true}
    {input {{"*bob*" "*fred*"} someName} want false}
    {input {{"*bob*" "*fred*"} somebobName} want true}
    {input {{"*bob*" "*fred*"} somefredName} want true}
    {input {{"*bob*" "*fred*"} someharroldName} want false}
  }
  xproc::testCases $t $cases {{input} {xproc::MatchCommandName {*}$input}}
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


proc xproc::ResetTest {commandName} {
  variable tests
  dict set tests $commandName skip false
  dict set tests $commandName fail false
}


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
