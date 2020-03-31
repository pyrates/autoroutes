"""Routes for speed"""
from pathlib import Path

from setuptools import Extension, setup

VERSION = (0, 3, 3)

setup(
    name="autoroutes",
    version=".".join(map(str, VERSION)),
    description=__doc__,
    long_description=Path("README.md").read_text(),
    long_description_content_type='text/markdown',
    author="Yohan Boniface",
    author_email="yohan.boniface@data.gouv.fr",
    url="https://github.com/pyrates/autoroutes",
    classifiers=[
        "License :: OSI Approved :: MIT License",
        "Intended Audience :: Developers",
        "Programming Language :: Python :: 3",
        "Operating System :: POSIX",
        "Operating System :: MacOS :: MacOS X",
        "Environment :: Web Environment",
        "Development Status :: 4 - Beta",
    ],
    platforms=["POSIX"],
    license="MIT",
    ext_modules=[
        Extension(
            "autoroutes",
            ["autoroutes.c"],
            extra_compile_args=["-O3"],  # Max optimization when compiling.
        )
    ],
    provides=["autoroutes"],
    include_package_data=True,
    extras_require={"dev": ["cython", "pytest"]},
)
