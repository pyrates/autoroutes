from setuptools import setup, Extension

setup(
    name='autoroutes',
    version='0.0.1',
    description='Routes for speed.',
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
    author='Yohan Boniface',
    author_email='yohan.boniface@data.gouv.fr',
    license='MIT',
    ext_modules=[
        Extension(
            'autoroutes',
            ['autoroutes.c'],
            extra_compile_args=['-O2']
        )
    ],
    provides=['autoroutes'],
    include_package_data=True
)
