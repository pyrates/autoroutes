"""Routes for speed"""
from pathlib import Path
from setuptools import setup, Extension

with Path(__file__).parent.joinpath('README.md').open(encoding='utf-8') as f:
    long_description = f.read()

VERSION = (0, 0, 1)

setup(
    name='autoroutes',
    version='.'.join(map(str, VERSION)),
    description=__doc__,
    long_description=long_description,
    author='Yohan Boniface',
    author_email='yohan.boniface@data.gouv.fr',
    url='https://framagit.org/ybon/autoroutes',
    classifiers=[
        'License :: OSI Approved :: MIT License',
        'Intended Audience :: Developers',
        'Programming Language :: Python :: 3',
        'Operating System :: POSIX',
        'Operating System :: MacOS :: MacOS X',
        'Environment :: Web Environment',
        'Development Status :: 4 - Beta',
    ],
    platforms=['POSIX'],
    license='MIT',
    ext_modules=[
        Extension(
            'autoroutes',
            ['autoroutes.c'],
            extra_compile_args=['-O3']
        )
    ],
    provides=['autoroutes'],
    include_package_data=True
)
