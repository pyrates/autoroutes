compile:
	cython autoroutes.pyx
	python setup.py build_ext --inplace

test:
	py.test -v

release: install test
	rm -rf dist/ build/ *.egg-info
	python -m build
	twine upload dist/*.tar.gz

install:
	pip install -e .[dev]
