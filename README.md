Artifact for "Relatively Complete Counterexamples for Higher-order Programs"
============================================================================

This repository contains the source code and benchmarks used to evaluate
the research done in *Relatively Complete Counterexamples for Higher-order Programs*
[accepted to PLDI 2015](https://github.com/philnguyen/soft-contract/blob/pldi-aec-2015/paper/pldi15-paper103.pdf).

We evaluate our method on programs written in an untyped functional language
representing [Core Racket](#supported-language)
and demonstrate its effectiveness against various common programming idioms.
The benchmarks are collected from different verification techniques on typed and untyped languages,
where benchmarks originally written in typed languages
are translated to untyped programs with contracts.
The tool itself is written in [Racket](http://racket-lang.org/).

There are three components to this artifact:

* An implementation of soft contract verification, which attempts
to verify or refute functional programs with behavioral contracts.
* A web REPL for interactively using the implementation.
* A test suite of 262 programs (involving 550 checks).

There are four options to evaluate the artifact, ordered in increasing
level of both involvement and confidence in reproducibility:

* By [inspecting the logs of our continuous integration server](#continuous-integration-results)
* By [interacting with the online evaluator](#try-the-online-evaluator)
* By [the self-contained Virtualbox image](#obtain-the-self-contained-virtualbox-image)
* By [cloning and building the repositories](#build-from-source-code)

## Continuous integration results

> https://travis-ci.org/philnguyen/soft-contract/

[![Build Status](https://travis-ci.org/philnguyen/soft-contract.png?branch=pldi-aec-2015)](https://travis-ci.org/philnguyen/soft-contract)

The implementation is built and tested from scratch on every commit.
The build will fail if any of the test suite programs produce
unexpected results.

We categorized programs into safe and unsafe.
Ideally, we should verify all safe programs
(in [`safe`](https://github.com/philnguyen/soft-contract/blob/pldi-aec-2015/soft-contract/benchmark-verification/safe))
and generate counterexamples for all unsafe ones
(in [`fail-ce`](https://github.com/philnguyen/soft-contract/blob/pldi-aec-2015/soft-contract/benchmark-verification/fail-ce)).
Unfortunately, verification is neccesarily incomplete in practice.
We therefore have two weaker categories
 * [`fail`](https://github.com/philnguyen/soft-contract/blob/pldi-aec-2015/soft-contract/benchmark-verification/fail):
   the verification should at least recognize that the program is potentially buggy,
   although it may not generate a counterexample (due to limitation of the underlying solver, for example)
 * [`no-ce`](https://github.com/philnguyen/soft-contract/blob/pldi-aec-2015/soft-contract/benchmark-verification/no-ce):
   the verification may fail to verify the correct program, reporting a *probable* contract violation, but it should not produce a counterexample.
   This category is currently empty.

Overtime, we move tests from `fail` and `no-ce` to the stronger categories `fail-ce` and `safe`,
respectively, and use integration testing to prevent regression in precision.

## Try the online evaluator

> http://scv.umiacs.umd.edu/

The quickest and most convenient way to test the artifact
is to use the [online evaluator](http://scv.umiacs.umd.edu/) hosted
at the University of Maryland, which provides a REPL for SCV Racket.
All of the benchmarks and examples are available to try or
you experiment with your own programs.

No identifying information is retained in the server logs, 
although we do record the programs entered
into the REPL for use as verification benchmarks.

## Obtain the self-contained Virtualbox image

The next most convenient method for testing the artifact is to download and run
a virtual machine that contains SCV Racket and all of its dependencies.

The image has been tested to work with Virtualbox `4.3.18`.
Instructions for [downloading and installing Virtualbox](https://www.virtualbox.org/wiki/Downloads)
can be found on the official site.

1. Download the [Virtualbox image](https://drive.google.com/file/d/0B5Xtjx9YdmWxQVc3THRkMGpVVlk/view?usp=sharing)
(~3.6 GB; hosted on Google Drive),
which contains built source code for `soft-contract`, the `try-scv-racket` web server, and benchmarks.

   Alternatively, you can download the
   [zipped version](https://drive.google.com/file/d/0B5Xtjx9YdmWxbVFZT05LQkJHcXM/view?usp=sharing)
   (~1.1 GB) of the same image if you have the software.

2. Launch Virtualbox:

  * Click `New`
  * Enter name and operating system:
    - Name: *(any name)*
	- Type: `Linux`
	- Version: `Ubuntu (32 bit)`
  * Next, set `Memory size`, recommended at least `1024MB`
  * Next, select `Use an existing virtual drive file`, then point to the downloaded disk image, then press `Create`
  * With the newly created machine selected, press `start`

2. The image runs Lubuntu 14.10 32 bit with log in information:

  * Username: `aec`
  * Password: `aec`

3. The desktop loads with a terminal popping up.

4. To run the benchmarks, type:

        test

   This runs the test suite and reports the run-time for each.
   The longest one runs in about 30 seconds.
   For bad programs, the tool also prints out counterexamples.
   At the end, you should see a summary:

        550 tests passed

   An example of the expected output from running the tests can be found at
   [`/home/aec/soft-contract/soft-contract/benchmark-verification/out.txt`](https://github.com/philnguyen/soft-contract/blob/pldi-aec-2015/soft-contract/benchmark-verification/out.txt)
   
5. The server already runs in the background.
   To try out the web tool, launch the browser from the `Google Chrome`
   desktop icon.
   Its homepage is set to `Try SCV`.

Miscellaneous information:

  * `/home/aec/soft-contract/soft-contract` contains the source code for the evaluator
  * `/home/aec/soft-contract/soft-contract/benchmark-verification` contains the benchmarks
  * `/home/aec/try-scv-racket` contains the source code for the web server
  * If the server dies, it can be restarted by executing:
  
        start-try-scv

## Build from source code

The final and most involved way to test the artifact is to download
and build the system yourself.

### Build the `soft-contract` repository

1. Obtain and install [Racket snapshot](http://www.cs.utah.edu/plt/snapshots/).

2. Obtain and install [Z3](http://z3.codeplex.com/)

3. Clone and build the repository

        git clone https://github.com/philnguyen/soft-contract.git
	    cd path/to/soft-contract/soft-contract
		raco pkg install

   Notice that you need to build from
   [`soft-contract/soft-contract`](https://github.com/philnguyen/soft-contract/blob/pldi-aec-2015/soft-contract/benchmark-verification/out.txt),
   not the outer directory.

4. Run the benchmarks. This step assumes `z3` is available in `$PATH`.

        cd path/to/soft-contract/soft-contract/benchmark-verification
	    raco test main.rkt

### Build the `try-scv-racket` server

This step assumes that you have built `soft-contract`
and performed `raco pkg install` as in the [previous section](#Build the `soft-contract` repository)

1. Clone the `try-scv-racket` repository

        git clone https://github.com/plum-umd/try-scv-racket.git

2. Launch the server at [http://localhost:8080](http://localhost:8080)

        racket path/to/try-scv-racket/main.rkt

## Supported Language

The demo currently supports the following subset of Racket:

    program          ::= sub-module-form … | sub-module-form … (require id …) expr
	sub-module-form  ::= (module module-id racket
	                       (provide provide-spec …)
                           (require require-spec …)
						   (struct id (id …)) …
                           (define id value) …)
    provide-spec     ::= id | (contract-out p/c-item …)
    p/c-item         ::= (id contract) | (struct id ([id contract] …))
	require-spec     ::= (submod ".." module-id)
	value            ::= (lambda (id …) expr) | number | boolean | string | symbol | op
	expr             ::= id | (if expr expr expr) | (expr expr …)
	contract         ::= expr | any/c | (or/c contract …) | (and/c contract …)
	                   | (>/c e) | (>=/c e) | (</c e) | (<=/c e) | (=/c e)
	                   | (list/c contract …) | (listof contract)
	                   | (->i ([id contract] …₁) (res (id …₁) contract))
					   | (struct/c id contract …)
    op               ::= + | - | * | / | string-length
	                   | number? | real? | integer? | boolean? | false? | cons? | empty?

Most forms are straightforward.
The contract combinators are used as follow:

* `expr` is any expression
* `any/c` matches any value
* `(list/c c …)` produces a contract for a fixed-length list whose elements
  matches the contracts `c …` pairwise.
* `(listof c)` produces a contract for an homogeneous list of any length
  whose elements match `c`.
* `or/c` and `and/c` produces disjunctive and conjunctive contracts, respectively
* `(>/c e)` produces a contract matching real numbers greater than the value
  evaluated to by `e`.
  Other combinators `>=/c`, `</c`, `<=/c` and `=/c` behave analogously.
* `(->i ([x cₓ] ...) (res (x …) d))`
  produces a function contract that if its arguments `(x …)` satisfy
  contracts `(cₓ …)`, produces a value satisfying contract `d`.
  This is a dependent contract, which means `x …` can appear free in `d`.
* `(struct/c id c …)` produces a contract matching values
  created by constructor `id` and each component matches contract `c`.
  
