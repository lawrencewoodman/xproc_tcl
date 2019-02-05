xproc
=====

[![Build Status](https://travis-ci.org/lawrencewoodman/xproc_tcl.svg?branch=master)](https://travis-ci.org/lawrencewoodman/xproc_tcl)

A Tcl extended proc module

This module extends `proc` to provide test and description functionality.


Requirements
------------
* Tcl 8.6+
* Tcllib

Installation
------------
To install the module you can use the [installmodule.tcl](https://github.com/LawrenceWoodman/installmodule_tcl) script or if you want to manually copy the file `ornament-*.tm` to a specific location that Tcl expects to find modules.

Testing
-------
There is a testsuite in `tests/`.  To run it:

    $ tclsh tests/all.tcl


Documentation
-------------
Descriptions of all the exported commands can be generated from the code using:

    $ tclsh utils/descriptions.tcl

Contributing
------------
I would love contributions to improve this project.  To do so easily I ask the following:

  * Please put your changes in a separate branch to ease integration.
  * For new code please add tests to prove that it works.
  * Update [CHANGELOG.md](https://github.com/lawrencewoodman/xproc_tcl/blob/master/CHANGELOG.md).
  * Make a pull request to the [repo](https://github.com/lawrencewoodman/xproc_tcl) on github.

If you find a bug, please report it at the project's [issues tracker](https://github.com/lawrencewoodman/xproc_tcl/issues) also on github.


Licence
-------
Copyright (C) 2019 Lawrence Woodman <lwoodman@vlifesystems.com>

This software is licensed under an MIT Licence.  Please see the file, [LICENCE.md](https://github.com/lawrencewoodman/xproc_tcl/blob/master/LICENCE.md), for details.
