#
# This is free and unencumbered software released into the public domain.
# See ../LICENSE.unlicense
#
# vim: noet sw=4 ts=4
#

TOP=../..

.PHONY: all
all:
	@echo This Makefile does not have an "all" target
	@echo Use the run_tests.sh script in the parent directory to run all tests
	@echo or use "make test_name.test" to run a single test.
	@false

.PRECIOUS: %.out
%.out : %.p $(TOP)/src/plzc
	if $(TOP)/src/plzc $< > $@ 2>&1 ; then \
		echo "Compilation succeeded" ; \
		echo "Compilation succeeded" >> $@ ; \
		false ; \
	fi

module_03.out : module_03a.pi
module_04a.out : module_04import.pi
module_04b.out : module_04import.pi
module_04c.out : module_04import.pi
module_04d.out : module_04import.pi

%.pzo : %.p $(TOP)/src/plzc
	$(TOP)/src/plzc $<

%.pzb : %.pzo $(TOP)/src/plzlnk
	$(TOP)/src/plzlnk -n ${subst .pzb,,$@} -o $@ $<

module_05.out : module_05.pzo module_05_.pzo
	if $(TOP)/src/plzlnk module_05.pzo module_05_.pzo \
			-n Module_05 -o module_05.pzb > $@ 2>&1 ; then \
		echo "Linking succeeded" ; \
		echo "Linking succeeded" >> $@ ; \
		false ; \
	fi

.PHONY: %.test
%.test : %.exp %.outs
	diff -u $^

%.outs : %.out
	grep -v '^#' < $< | sed -e 's/#.*$$//' > $@

.PHONY: clean
clean:
	rm -rf *.pzb *.pzo *.out *.diff *.log *.trace

.PHONY: realclean
realclean: clean
	rm -rf *.plasma-dump_*

