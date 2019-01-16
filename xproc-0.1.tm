# An extended proc implementation
#
# Copyright (C) 2019 Lawrence Woodman <lwoodman@vlifesystems.com>
# Licensed under an MIT licence.  Please see LICENCE.md for details.

package require Tcl 8.6

namespace eval xproc {
  namespace export {[a-z]*}
  variable tests [dict create]
  variable testFailMessages {}
  variable descriptions [dict create]
}


###################################################################
# Descriptions and tests for exported procedures are at the end
# of this file because certain functions need to be defined before
# xproc can be used to add the descriptions.
###################################################################


proc xproc::proc {procName procArgs procBody args} {
  array set options {}
  while {[llength $args]} {
    switch -glob -- [lindex $args 0] {
      -desc* {set args [lassign $args - options(description)]}
      -test {set args [lassign $args - options(test)]}
      -*      {return -code error "unknown option [lindex $args 0]"}
      default break
    }
  }
  if {[llength $args] > 0} {
    return -code error "invalid number of arguments"
  }

  uplevel 1 [list proc $procName $procArgs $procBody]

  if {[info exists options(description)]} {
    uplevel 1 [list xproc::describe $procName $options(description)]
  }

  if {[info exists options(test)]} {
    uplevel 1 [list xproc::test $procName $options(test)]
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
    dict filter $d script {procName -} {
      expr {![MatchProcName $matchPatterns $procName]}
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
    default {return -code error "unknown type: $type"}
  }
}


proc xproc::test {procName lambda} {
  variable tests
  set fullProcName [
    uplevel 1 [list namespace which -command $procName]
  ]
  dict set tests $fullProcName [dict create lambda $lambda]
}


proc xproc::describe {procName description} {
  variable descriptions
  set fullProcName [
    uplevel 1 [list namespace which -command $procName]
  ]
  dict set descriptions $fullProcName [TidyDescription $description]
}


proc xproc::runTests {args} {
  variable tests
  variable testFailMessages

  array set options {verbose 1 match {"*"}}
  while {[llength $args]} {
    switch -glob -- [lindex $args 0] {
      -match {set args [lassign $args - options(match)]}
      -verbose {set args [lassign $args - options(verbose)]}
      -*      {return -code error "unknown option [lindex $args 0]"}
      default break
    }
  }
  if {[llength $args] > 0} {
    return -code error "invalid number of arguments"
  }

  set newTests [
    dict map {procName test} $tests {
      set testFailMessages {}
      dict set test skip false
      if {![MatchProcName $options(match) $procName]} {
        dict set test skip true
        if {$options(verbose) >= 2} {
          puts "=== SKIP   $procName"
        }
      } else {
        set timeStart [clock microseconds]
        if {$options(verbose) >= 2} {
          puts "=== RUN   $procName"
        }
        try {
          set lambda [dict get $test lambda]
          uplevel 1 [list apply $lambda $procName]
        } on error {result returnOptions} {
          set errorInfo [dict get $returnOptions -errorinfo]
          lappend testFailMessages $errorInfo
        }
        set secondsElapsed [
          expr {([clock microseconds] - $timeStart)/1000000.}
        ]
        if {[llength $testFailMessages] > 0} {
          if {$options(verbose) >= 1} {
            puts [format {--- FAIL  %s (%0.2fs)} $procName $secondsElapsed]
            foreach msg $testFailMessages {
              puts [IndentEachLine $msg 10 0]
            }
          }
        } else {
          if {$options(verbose) >= 2} {
            puts [format {--- PASS  %s (%0.2fs)} $procName $secondsElapsed]
          }
        }
      }
      dict set test fail [expr {[llength $testFailMessages] > 0}]
    }
  ]
  set tests $newTests
  set summary [MakeSummary $newTests]
  if {$options(verbose) >= 1} {
    dict with summary {
      puts "\nTotal: $total,  Passed: $passed,  Skipped: $skipped,  Failed: $failed"
    }
  }
  return $summary
}


proc xproc::testFail {testState msg} {
  variable testFailMessages
  lappend testFailMessages $msg
}


proc xproc::testCases {testState cases lambdaExpr} {
  set i 0
  foreach c $cases {
    set input [dict get $c input]
    set result [dict get $c result]
    set returnCodes {ok return}
    if {[dict exists $c returnCodes]} {
      set returnCodes [dict get $c returnCodes]
    }
    set returnCodes [lmap code $returnCodes {ReturnCodeToValue $code}]
    try {
      set got [uplevel 1 [list apply $lambdaExpr $input]]
      if {$got ne $result} {
        xproc::testFail $testState "($i) got: $got, want: $result"
      }
    } on error {got returnOptions} {
      if {$got != $result} {
        xproc::testFail $testState "($i) got: $got, want: $result"
      }
      set returnCode [dict get $returnOptions -code]
      set wantCodeFound false
      foreach wantCode $returnCodes {
        if {$returnCode == $wantCode} {
          set wantCodeFound true
          break
        }
      }
      if {!$wantCodeFound} {
        xproc::testFail $testState \
            "($i) got return code: $returnCode, want one of: $returnCodes"
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

  dict filter $descriptions script {procName description} {
    MatchProcName $options(match) $procName
  }
}


xproc::proc xproc::ReturnCodeToValue {code} {
  set returnCodeValues {ok 0 error 1 return 2 break 3 continue 4}
  if {[dict exists $returnCodeValues $code]} {
    return [dict get $returnCodeValues $code]
  }
  return $code
} -test {{t} {
  set cases {
    {input ok result 0}
    {input error result 1}
    {input return result 2}
    {input break result 3}
    {input continue result 4}
    {input fred result fred}
    {input 0 result 0}
    {input 7 result 7}
  }
  xproc::testCases $t $cases {{input} {xproc::ReturnCodeToValue $input}}
}}


xproc::proc xproc::MakeSummary {tests} {
  set total [llength [dict keys $tests]]
  set failed 0
  set skipped 0
  dict for {procName test} $tests {
    if {[dict get $test fail]} {incr failed}
    if {[dict get $test skip]} {incr skipped}
  }
  set passed [expr {($total-$failed)-$skipped}]
  return [dict create \
               total $total passed $passed skipped $skipped failed $failed]
} -test {{t} {
  set cases [list \
    [dict create input {} \
     result [dict create total 0 passed 0 skipped 0 failed 0]] \
    [dict create input {name-1 {skip false fail true}} \
     result [dict create total 1 passed 0 skipped 0 failed 1]] \
    [dict create input {name-1 {skip false fail false}} \
     result [dict create total 1 passed 1 skipped 0 failed 0]] \
    [dict create input {name-1 {skip false fail false} \
                        name-2 {skip false fail false}} \
     result [dict create total 2 passed 2 skipped 0 failed 0]] \
    [dict create input {name-1 {skip false fail true} \
                        name-2 {skip false fail false}} \
     result [dict create total 2 passed 1 skipped 0 failed 1]] \
    [dict create input {name-1 {skip false fail false} \
                        name-2 {skip false fail true}} \
     result [dict create total 2 passed 1 skipped 0 failed 1]] \
    [dict create input {name-1 {skip false fail true} \
                        name-2 {skip false fail true}} \
     result [dict create total 2 passed 0 skipped 0 failed 2]] \
    [dict create input {name-1 {skip true fail false} \
                        name-2 {skip false fail true}} \
     result [dict create total 2 passed 0 skipped 1 failed 1]] \
    [dict create input {name-1 {skip true fail false} \
                        name-2 {skip true fail false}} \
     result [dict create total 2 passed 0 skipped 2 failed 0]] \
  ]
  xproc::testCases $t $cases {{input} {xproc::MakeSummary $input}}
}}


# Does procName match any of the patterns
xproc::proc xproc::MatchProcName {matchPatterns procName} {
  foreach matchPattern $matchPatterns {
    if {[string match $matchPattern $procName]} {return true}
  }
  return false
} -test {{t} {
  set cases {
    {input {{"*"} someName} result true}
    {input {{"*bob*" "*"} someName} result true}
    {input {{"*bob*" "*fred*"} someName} result false}
    {input {{"*bob*" "*fred*"} somebobName} result true}
    {input {{"*bob*" "*fred*"} somefredName} result true}
    {input {{"*bob*" "*fred*"} someharroldName} result false}
  }
  xproc::testCases $t $cases {{input} {xproc::MatchProcName {*}$input}}
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
    {input {hello this is some text} result 0}
    {input {  hello this is some text} result 2}
    {input {  hello this is some text   } result 2}
    {input {    hello this is some text } result 4}
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
      } 0} result {
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
      } 1} result {
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
      } 2} result {
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
      } 3} result {
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
      if {[llength $got] != [llength $result]} {
        xproc::testFail $t "($i) got: $got, want: $result"
      } else {
        foreach g $got w $result {
          if {$g ne $w} {
            xproc::testFail $t "($i) got: $got, want: $result"
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
      result {this is a description}}
    { input {
        this is a description
      }
      result {this is a description}}
    { input {
        this is a description

        this is some more text on another
        line to see if everything is aligned properly
          this text is indent further

          as is this line
            even futher down here
      }
      result {this is a description

this is some more text on another
line to see if everything is aligned properly
  this text is indent further

  as is this line
    even futher down here}}
    { input {this is a description without a leading newline

        this is some more text on another
        line to see if everything is aligned properly
      }
      result {this is a description without a leading newline

        this is some more text on another
        line to see if everything is aligned properly}}
  }

  xproc::testCases $t $cases {{input} {xproc::TidyDescription $input}}
}}




##################################################
# Tests and Descriptions for exported procedures
##################################################

xproc::describe xproc::proc {
  Create a Tcl procedure, like ::proc, but extended with extra switches

  xproc::proc name args body ?-description description? ?-test lambda?

  This extendeds ::proc by adding the following switches:
    -description description   Records the given description
    -test lambda               Records the given lambda to be used
                               to test this procedure.  The lambda has
                               one parameter which is the testState.
}

xproc::test xproc::proc {{t} {
  # Check errors
  set cases {
    {input {xproc::Dummy-1 {} {} -bob}
     returnCodes {error} result "unknown option -bob"}
    {input {xproc::Dummy-2 {} {} bob}
     returnCodes {error} result "invalid number of arguments"}
  }
  xproc::testCases $t $cases {{input} {xproc::proc {*}$input}}

  try {
    # Check -test and -description
    xproc::proc xproc::Dummy-3 {a b} {
      expr {$a+$b}
    } -test {{t} {
      set got [xproc::Dummy-3 2 3]
      set want 5
      if {$got != $want} {
        xproc::testFail $t "got: $got, want: $want"
      }
    }} -description {Add two numbers together}
    set gotSummary [xproc::runTests -match {::xproc::Dummy-*} -verbose 0]
    dict with gotSummary {
      if {$passed != 1 || $failed != 0 || $total < 5 || $total > 100} {
        xproc::testFail $t "summary incorrect - got: $gotSummary"
      }
    }
    set gotDescriptions [xproc::descriptions -match {::xproc::Dummy-*}]
    set wantDescriptions [
      dict create ::xproc::Dummy-3 {Add two numbers together}
    ]
    if {$gotDescriptions ne $wantDescriptions} {
      xproc::testFail $t \
          "descriptions - got: $gotDescriptions, want: $wantDescriptions"
    }
  } finally {
    xproc::remove all -match {::xproc::Dummy-*}
    rename xproc::Dummy-3 ""
  }
}}


xproc::describe xproc::remove {
  Remove xproc functionality from procedures

  xproc::remove type ?-match patternList?

  The type can be one of:
    tests           Remove tests
    descriptions    Remove descriptions
    all             Remove all xproc functionality

  There is one switch:
    -match patternList    Matches procedureNames against patterns in
                          patternList, the default is {"*"}
}

xproc::test xproc::remove {{t} {
  # Check errors
  set cases {
    {input {all -fred}
     returnCodes {error} result "unknown option -fred"}
    {input {bob}
     returnCodes {error} result "unknown type: bob"}
  }
  xproc::testCases $t $cases {{input} {xproc::proc {*}$input}}

  try {
    for {set n 1} {$n <= 3} {incr n} {
      xproc::proc xproc::Dummy-$n {a b} {
        expr {$a+$b}
      } -test {{t} {
        set got [xproc::Dummy-3 2 3]
        set want 5
        if {$got != $want} {
          xproc::testFail $t "got: $got, want: $want"
        }
      }} -description {Add two numbers together}
    }
    xproc::remove tests -match *Dummy-2
    set gotSummary [xproc::runTests -match {::xproc::Dummy-*} -verbose 0]
    dict with gotSummary {
      if {$passed != 2 || $failed != 0 || $total < 5 || $total > 100} {
        xproc::testFail $t "after remove tests Dummy-2 - summary incorrect - got: $gotSummary"
      }
    }
    xproc::remove descriptions -match *Dummy-3
    set gotDescriptions [xproc::descriptions -match {::xproc::Dummy-*}]
    set gotDescriptionProcNames [dict keys $gotDescriptions]
    set wantDescriptionProcNames {::xproc::Dummy-1 ::xproc::Dummy-2}
    if {$gotDescriptionProcNames ne $wantDescriptionProcNames} {
      xproc::testFail $t \
          "after remove descriptions Dummy-3 - descriptions - got keys: $gotDescriptionProcNames, want: $wantDescriptionProcNames"
    }
    xproc::remove all -match {::xproc::Dummy-*}
    set gotSummary [xproc::runTests -match {::xproc::Dummy-*} -verbose 0]
    dict with gotSummary {
      if {$passed != 0 || $failed != 0 || $total < 5 || $total > 100} {
        xproc::testFail $t "after remove all Dummy-* - summary incorrect - got: $gotSummary"
      }
    }
    set gotDescriptions [xproc::descriptions -match {::xproc::Dummy-*}]
    set gotDescriptionProcNames [dict keys $gotDescriptions]
    if {[llength $gotDescriptionProcNames] != 0} {
      xproc::testFail $t \
          "after remove descriptions all Dummy-* descriptions - got keys: $gotDescriptionProcNames, want: $wantDescriptionProcNames"
    }
  } finally {
    xproc::remove all -match {::xproc::Dummy-*}
    rename xproc::Dummy-1 ""
    rename xproc::Dummy-2 ""
    rename xproc::Dummy-3 ""
  }
}}


xproc::describe xproc::test {
  Record the given lambda to test a procedure

  xproc::test procedureName lambda

  The lambda has one parameter which is the testState
}

xproc::describe xproc::describe {
  Record the given description for a procedure

  xproc::describe procedureName description
}

xproc::describe xproc::runTests {
  Run the tests recorded using xproc

  xproc::runTests ?-verbose? ?-match patternList?

  The switches do the following:
    -verbose level        Controls the level of output to stdout:
                            0  None
                            1  Summary and failing tests
                            2  Summary and all tests
                          The default is 1
    -match patternList    Matches procedureNames against patterns in
                          patternList, the default is {"*"}
}

xproc::describe xproc::testFail {
  Output a FAIL message and record that test has failed

  xproc::testFail procedureName msg
}


xproc::describe xproc::testCases {
  Test the supplied test cases within a test lambda

  xproc::testCases testState cases lambda

  The testState is passed through a test lambda defined with xproc::test
  or using -test with xproc::proc.

  The cases are a list of dictionaries that describe each test case with
  the following keys:
    input        The value to pass to the lambda
    result       The value to test against the result of the lambda
    returnCodes  Return codes to test against, the default is {ok return}

  The lambda has one parameter which is the input for the test case.
}

xproc::describe xproc::descriptions {
  Return the descriptions recorded using xproc

  xproc::descriptions ?-match patternList?

  There is one switch:
    -match patternList    Matches procedureNames against patterns in
                          patternList, the default is {"*"}
}
