#    This file is part of Plumbum 1.0.
#    Copyright (C) 2018  Carine Dengler
#
#    Plumbum is free software: you can redistribute it and/or modify
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
:synopsis: Plumbum shell.
"""


# standard library imports
import os
import cmd
import subprocess
import readline

# third party imports
# library specific imports
import src.dev


class PlumbumShell(cmd.Cmd):
    """Plumbum shell.

    :cvar str prompt: prompt
    :ivar Device device: DVD device interface
    """
    prompt = "(plumbum) "

    def __init__(self):
        """Initialize Plumbum shell."""
        super().__init__()
        self.device = src.dev.Device()
        return

    def do_list(self, arg):
        """List titles."""
        titles = "\n".join(
            "{}\t: {}".format(value["name"], value["info"])
            for _, value in self.device.titles.items()
        )
        print(titles)
        return

    def do_rename(self, arg):
        """Rename titles."""
        try:
            for title in arg.split(" "):
                name = input("{}{}\t: ".format(self.prompt, title))
                if title in self.device.titles:
                    self.device.titles[title]["name"] = name
                else:
                    raise RuntimeError("no title {}".format(title))
        except RuntimeError as exception:
            print(exception)
        except Exception:
            raise
        return

    def do_bye(self, arg):
        """Close plumbum shell."""
        print("Thank you for using Plumbum")
        return True
