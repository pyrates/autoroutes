compile:
	cython autoroutes.pyx
	python setup.py build_ext --inplace

test:
	py.test -v

release: compile test
	rm -rf dist/ build/ *.egg-info
	python setup.py sdist upload

install:
	pip install -e .[dev]
