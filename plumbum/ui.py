#    This file is part of Plumbum 1.0.
#    Copyright (C) 2018  Carine Dengler and Michael Herbst
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
import cmd

# third party imports
# library specific imports
from . import dev


class PlumbumShell(cmd.Cmd):
    """Plumbum shell.

    :cvar str prompt: prompt
    :ivar Device device: DVD device interface
    """
    prompt = "(pb) "

    def __init__(self):
        """Initialize Plumbum shell."""
        super().__init__()
        self.device = dev.Device()
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

    def do_rip(self, arg):
        """Rip titles."""
        try:
            titles = arg.split(" ")
            if titles:
                pass
            else:
                titles = list(self.device.titles.keys())
            self.device.rip(titles)
        except RuntimeError as exception:
            print(exception)
        except Exception:
            raise
        return

    def do_bye(self, arg):
        """Close plumbum shell."""
        print()
        print("Thank you for using Plumbum")
        return True

    do_quit = do_bye
    do_EOF = do_bye
