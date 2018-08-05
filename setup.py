"""Setup for plumbum"""

# Use setuptools for these commands (they don't work well or at all
# with distutils).  For normal builds use distutils.
try:
    from setuptools import setup
except ImportError:
    from distutils.core import setup

setup(
    name='plumbum',
    description="Interactively rip a DVD",
    long_description="Command line tool for ripping a DVD",
    #
    url='https://github.com/mfherbst/plumbum',
    author='Michael F. Herbst',
    author_email="info@michael-herbst.com",
    maintainer="Carine Dengler",
    maintainer_email="pascaline@pascalin.de",
    license="GPL v3",
    #
    packages=['plumbum'],
    scripts=["bin/pb"],
    version='0.0.0',
    #
    python_requires='>=3',
    install_requires=[],
    extras_require={
        "desktop_notifications": ["notify2 (>=0.3)", "dbus-python (>= 1.2.8)"],
    },
    classifiers=[
        'Development Status :: 3 - Alpha',
        'Environment :: Console',
        'License :: OSI Approved :: GNU General Public License v3 (GPLv3)',
        'Intended Audience :: Science/Research',
        'Topic :: Multimedia :: Video :: Conversion',
        'Programming Language :: Python :: 3.5',
        'Programming Language :: Python :: 3.6',
        'Operating System :: Unix',
    ],
)
