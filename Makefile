compile:
	cython autoroutes.pyx
	python setup.py build_ext --inplace

test:
	py.test -v

release:
	rm -rf dist/ build/ *.egg-info
	python setup.py sdist bdist_wheel upload
