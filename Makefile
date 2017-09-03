compile:
	cython autoroutes.pyx
	python setup.py build_ext --inplace

test:
	py.test -v
