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


###################################################################
# Descriptions for exported procedures are at the end
# of this file because certain functions need to be defined before
# xproc can be used to add the descriptions.
###################################################################


proc xproc::proc {procName procArgs procBody args} {
  array set options {}
  while {[llength $args]} {
    switch -glob -- [lindex $args 0] {
      -desc* {set args [lassign $args - options(description)]}
      -test {set args [lassign $args - options(test)]}
      -*      {return -code error "unknown option: [lindex $args 0]"}
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
      -*      {return -code error "unknown option: [lindex $args 0]"}
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


proc xproc::test {args} {
  variable tests
  array set options {id 1}
  while {[llength $args]} {
    switch -glob -- [lindex $args 0] {
      -id {set args [lassign $args - options(id)]}
      --      {set args [lrange $args 1 end] ; break}
      -*      {return -code error "unknown option: [lindex $args 0]"}
      default break
    }
  }
  if {![string is integer $options(id)] || $options(id) < 1} {
    return -code error "invalid id: $options(id)"
  }
  if {[llength $args] != 2} {
    return -code error "invalid number of arguments"
  }

  lassign $args procName lambda

  set fullProcName [
    uplevel 1 [list namespace which -command $procName]
  ]
  if {$fullProcName eq ""} {
    return -code error "procedureName doesn't exist: $procName"
  }

  if {[dict exists $tests $fullProcName $options(id)]} {
    return -code error "test already exists for id: $options(id)"
  }

  dict set tests $fullProcName $options(id) [dict create lambda $lambda]
}


proc xproc::describe {procName description} {
  variable descriptions
  set fullProcName [
    uplevel 1 [list namespace which -command $procName]
  ]
  if {$fullProcName eq ""} {
    return -code error "procedureName doesn't exist: $procName"
  }
  dict set descriptions $fullProcName [TidyDescription $description]
}


proc xproc::runTests {args} {
  variable tests

  array set options {channel stdout match {"*"} verbose 1}
  while {[llength $args]} {
    switch -glob -- [lindex $args 0] {
      -channel {set args [lassign $args - options(channel)]}
      -match {set args [lassign $args - options(match)]}
      -verbose {set args [lassign $args - options(verbose)]}
      -*      {return -code error "unknown option: [lindex $args 0]"}
      default break
    }
  }
  if {[llength $args] > 0} {
    return -code error "invalid number of arguments"
  }
  set newTests [
    dict map {procName procTests} $tests {
      dict map {id test} $procTests {
        RunTest $procName $test $id $options(verbose) \
                $options(channel) $options(match)
      }
    }
  ]
  set tests $newTests
  set summary [MakeSummary $newTests]
  if {$options(verbose) >= 1} {
    dict with summary {
      puts $options(channel) \
      "\nTotal: $total,  Passed: $passed,  Skipped: $skipped,  Failed: $failed"
    }
  }
  return $summary
}


proc xproc::descriptions {args} {
  variable descriptions
  array set options {match {"*"}}
  while {[llength $args]} {
    switch -glob -- [lindex $args 0] {
      -match {set args [lassign $args - options(match)]}
      -*      {return -code error "unknown option: [lindex $args 0]"}
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


proc xproc::tests {args} {
  variable tests
  array set options {match {"*"}}
  while {[llength $args]} {
    switch -glob -- [lindex $args 0] {
      -match {set args [lassign $args - options(match)]}
      -*      {return -code error "unknown option: [lindex $args 0]"}
      default break
    }
  }
  if {[llength $args] > 0} {
    return -code error "invalid number of arguments"
  }

  dict filter $tests script {procName lambda} {
    MatchProcName $options(match) $procName
  }
}


proc xproc::testCases {testRun cases lambda} {
  set i 0
  foreach case $cases {
    set returnCodes {ok return}
    if {[dict exists $case returnCodes]} {
      set returnCodes [dict get $case returnCodes]
    }
    set returnCodes [lmap code $returnCodes {ReturnCodeToValue $code}]
    try {
      set got [uplevel 1 [list apply $lambda $case]]
      if {[dict exists $case result]} {
        set result [dict get $case result]
        if {$got ne $result} {
          fail $testRun "($i) got: $got, want: $result"
        }
      }
    } on error {got returnOptions} {
      if {[dict exists $case result]} {
        set result [dict get $case result]
        if {$got ne $result} {
          fail $testRun "($i) got: $got, want: $result"
        }
      } else {
        fail $testRun "($i) $got"
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
        fail $testRun \
            "($i) got return code: $returnCode, want one of: $returnCodes"
      }
    }
    incr i
  }
}


proc xproc::fail {testRun msg} {
  TestRun fail $testRun $msg
}



###########################
# Unexported commands
###########################

namespace eval xproc::TestRun {
  namespace export {[a-z]*}
  namespace ensemble create
  variable runs {}
  variable n 0
}

proc xproc::TestRun::new {} {
  variable runs
  variable n
  dict set runs [incr n] [dict create failMessages {}]
  return $n
}

proc xproc::TestRun::fail {testRun msg} {
  variable runs
  set oldFailMessages [dict get $runs $testRun failMessages]
  dict set runs $testRun failMessages [list {*}$oldFailMessages $msg]
}

proc xproc::TestRun::failMessages {testRun} {
  variable runs
  return [dict get $runs $testRun failMessages]
}

proc xproc::TestRun::hasFailed {testRun} {
  variable runs
  return [expr {[llength [dict get $runs $testRun failMessages]] > 0}]
}


proc xproc::RunTest {procName test id verbose channel match} {
  dict set test skip false
  dict set test fail false

  # TODO: This isn't great as checking for each id-test
  if {![MatchProcName $match $procName]} {
    dict set test skip true
    if {$verbose >= 2} {
      puts $channel "=== SKIP   $procName/$id"
    }
    return $test
  }

  set testRun [TestRun new]
  if {$verbose >= 2} {
    puts $channel "=== RUN   $procName/$id"
  }
  set timeStart [clock microseconds]
  try {
    uplevel 1 [list apply [dict get $test lambda] $testRun]
  } on error {result returnOptions} {
    set errorInfo [dict get $returnOptions -errorinfo]
    fail $testRun $errorInfo
  }
  set secondsElapsed [
    expr {([clock microseconds] - $timeStart)/1000000.}
  ]
  if {[TestRun hasFailed $testRun]} {
    if {$verbose >= 1} {
      puts $channel [
        format {--- FAIL  %s/%s (%0.2fs)} $procName $id $secondsElapsed
      ]
      foreach msg [TestRun failMessages $testRun] {
        puts $channel [IndentEachLine $msg 10 0]
      }
    }
  } else {
    if {$verbose >= 2} {
      puts $channel [
        format {--- PASS  %s/%s (%0.2fs)} $procName $id $secondsElapsed
      ]
    }
  }
  dict set test fail [TestRun hasFailed $testRun]
  return $test
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
  xproc::testCases $t $cases {{case} {
    dict with case {xproc::ReturnCodeToValue $input}
  }}
}}


xproc::proc xproc::MakeSummary {tests} {
  set total 0
  set failed 0
  set skipped 0
  dict for {procName procTests} $tests {
    dict for {id test} $procTests {
      incr total
      if {[dict get $test fail]} {incr failed}
      if {[dict get $test skip]} {incr skipped}
    }
  }
  set passed [expr {($total-$failed)-$skipped}]
  return [dict create \
               total $total passed $passed skipped $skipped failed $failed]
} -test {{t} {
  set cases [list \
    [dict create input {} \
     result [dict create total 0 passed 0 skipped 0 failed 0]] \
    [dict create input {name-1 {0 {skip false fail true}}} \
     result [dict create total 1 passed 0 skipped 0 failed 1]] \
    [dict create input {name-1 {0 {skip false fail false}}} \
     result [dict create total 1 passed 1 skipped 0 failed 0]] \
    [dict create input {name-1 {0 {skip false fail false}} \
                        name-2 {0 {skip false fail false}}} \
     result [dict create total 2 passed 2 skipped 0 failed 0]] \
    [dict create input {name-1 {0 {skip false fail true}} \
                        name-2 {0 {skip false fail false}}} \
     result [dict create total 2 passed 1 skipped 0 failed 1]] \
    [dict create input {name-1 {0 {skip false fail false}} \
                        name-2 {0 {skip false fail true}}} \
     result [dict create total 2 passed 1 skipped 0 failed 1]] \
    [dict create input {name-1 {0 {skip false fail true}} \
                        name-2 {0 {skip false fail true}}} \
     result [dict create total 2 passed 0 skipped 0 failed 2]] \
    [dict create input {name-1 {0 {skip true fail false}} \
                        name-2 {0 {skip false fail true}}} \
     result [dict create total 2 passed 0 skipped 1 failed 1]] \
    [dict create input {name-1 {0 {skip true fail false}} \
                        name-2 {0 {skip true fail false}}} \
     result [dict create total 2 passed 0 skipped 2 failed 0]] \
    [dict create input [
      dict create name-1 [dict create 0 {skip true fail false} \
                                      1 {skip false fail true}] \
                  name-2 [dict create 0 {skip true fail false} \
                                      1 {skip false fail false}] \
      ] result [dict create total 4 passed 1 skipped 2 failed 1]] \
  ]
  xproc::testCases $t $cases {{case} {
    dict with case {xproc::MakeSummary $input}
  }}
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
  xproc::testCases $t $cases {{case} {
    dict with case {xproc::MatchProcName {*}$input}
  }}
}}


xproc::proc xproc::IndentEachLine {text numSpaces ignoreLines} {
  set lines [split $text "\n"]
  set indentedLines {}
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
    xproc::fail $t "got: $got, want: $want"
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
  xproc::testCases $t $cases {{case} {
    dict with case {xproc::CountIndent $input}
  }}
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
        xproc::fail $t "($i) got: $got, want: $result"
      } else {
        foreach g $got w $result {
          if {$g ne $w} {
            xproc::fail $t "($i) got: $got, want: $result"
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

  xproc::testCases $t $cases {{case} {
    dict with case {xproc::TidyDescription $input}
  }}
}}




##################################################
# Descriptions for exported procedures
##################################################

xproc::describe xproc::proc {
  Create a Tcl procedure, like ::proc, but extended with extra switches

  xproc::proc name args body ?-description description? ?-test lambda?

  This extendeds ::proc by adding the following switches:
    -description description   Records the given description
    -test lambda               Records the given lambda to be used
                               to test this procedure.  The lambda has
                               one parameter which is the testRun.
}

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

xproc::describe xproc::testCases {
  Test the supplied test cases within a test lambda

  xproc::testCases testRun cases lambda

  The testRun is passed through a test lambda defined with xproc::test
  or using -test with xproc::proc.

  The cases are a list of dictionaries that describe each test case with
  the following keys:
    input        The value to pass to the lambda
    result       The value to test against the result of the lambda
    returnCodes  Return codes to test against, the default is {ok return}
  Extra keys may be present and therefore passed to the lambda.

  The lambda has one parameter which is the test case.
}


xproc::describe xproc::fail {
  Output a FAIL message and record that test has failed

  xproc::fail testRun msg

  This is to be called within a test lambda.
}


xproc::describe xproc::test {
  Record the given lambda to test a procedure

  xproc::test ?switches? procedureName lambda

  The switches do the following:
    -id id    Give an id to the test to allow multiple tests
              for a procedureName.  The default is 1.
    --        Marks the end of switches

  The lambda has one parameter which is the testRun
}

xproc::describe xproc::describe {
  Record the given description for a procedure

  xproc::describe procedureName description

  A description shouldn't contain tabs as it will cause text
  alignment issues.
}

xproc::describe xproc::runTests {
  Run the tests recorded using xproc

  xproc::runTests ?-verbose? ?-match patternList?

  The switches do the following:
    -channel channelID    A channel to send output to. The default is stdout.
    -match patternList    Matches procedureNames against patterns in
                          patternList, the default is {"*"}
    -verbose level        Controls the level of output to stdout:
                            0  None
                            1  Summary and failing tests
                            2  Summary and all tests
                          The default is 1
}


xproc::describe xproc::descriptions {
  Return the descriptions recorded using xproc

  xproc::descriptions ?-match patternList?

  There is one switch:
    -match patternList    Matches procedureNames against patterns in
                          patternList, the default is {"*"}

  The return value is a dictionary with the procedureNames as the
  key and the description as the value.
}

xproc::describe xproc::tests {
  Return the tests recorded using xproc

  xproc::tests ?-match patternList?

  There is one switch:
    -match patternList    Matches procedureNames against patterns in
                          patternList, the default is {"*"}

  The return value is a dictionary with the procedureNames as the
  key.
}
