namespace eval TestHelpers {}

# This is used to capture the output of a channel
namespace eval TestHelpers::channelMonitor {
  namespace export {[a-z]*}
  namespace ensemble create
  variable channels
}

proc TestHelpers::channelMonitor::new {} {
  variable channels
  return [chan create {write} \
    [namespace which -command TestHelpers::channelMonitor]
  ]
}

proc TestHelpers::channelMonitor::initialize {channelID mode} {
  variable channels
  if {"read" in $mode} {
    return -code error "unsupported mode: read"
  }
  dict set channels $channelID [
    dict create writeData {} finalized false
  ]
  return {initialize finalize watch write}
}

proc TestHelpers::channelMonitor::finalize {channelID} {
  variable channels
  dict unset channels $channelID
}

proc TestHelpers::channelMonitor::watch {channelID eventSpec} {
}

proc TestHelpers::channelMonitor::write {channelID data} {
  variable channels
  set channelWriteData [dict get $channels $channelID writeData]
  append channelWriteData $data
  dict set channels $channelID writeData $channelWriteData
  return [string bytelength $data]
}

proc TestHelpers::channelMonitor::getWriteData {channelID} {
  variable channels
  flush $channelID
  return [dict get $channels $channelID writeData]
}

proc TestHelpers::addNums {args} {
  return [::tcl::mathop::+ {*}$args]
}
