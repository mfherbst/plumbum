#    This file is part of plumbum 1.0.
#    Copyright (C) 2018  Carine Dengler and Michael Herbst
#
#    plumbum is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.


"""
:synopsis:
"""


# standard library imports
import sys

# third party imports
import notify2

# library specific imports
import src.ui


def main():
    """main function."""
    try:
        intro = (
            "Welcome to the Plumbum shell.\t"
            "Type help or ? to list commands.\n"
            "Using SCSI CD-ROM device\t: {}"
        )
        plumbum_shell = src.ui.PlumbumShell()
        plumbum_shell.cmdloop(
            intro=intro.format(plumbum_shell.device.device)
        )
        prog = sys.argv[0].split("/")[-1]
        notify2.init(prog)
        msg = "finished execution"
        notification = notify2.Notification(prog, message=msg)
        notification.show()
    except Exception:
        raise
    return


if __name__ == "__main__":
    main()
