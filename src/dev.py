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
:synopsis: DVD driver interface.
"""


# standard library imports
import os
import re
import subprocess

# third party imports
# library specific imports


class Device(object):
    """DVD device interface.

    :cvar str PATH: PATH
    :cvar str DUMPFILE: dumpfile
    :cvar str CHAPTERINFO: chapter information

    :ivar str device: DVD device
    :ivar dict titles: DVD titles
    """
    PATH = "dvd://{}//{}"
    DUMPFILE = "dump{}.vob"
    CHAPTERINFO = "chapterinfo{}.txt"

    def __init__(self, device=""):
        """Initialize DVD device interface.

        :param str device: DVD device
        """
        self.device = self.get_device(device)
        self.titles = self.get_titles()
        return

    def get_device(self, device=""):
        """Get DVD device.

        :param str device: DVD device

        :returns: DVD device
        :rtype: str
        """
        try:
            devices = self._get_dev_sr()
            if device in devices:
                pass
            elif device:
                raise RuntimeError(
                    "no DVD device {} in device files".format(device)
                )
            elif len(devices) == 0:
                raise RuntimeError("no DVD device")
            elif len(devices) == 1:
                device = devices[0]
            elif len(devices) > 1:
                raise RuntimeError("more than one DVD device")
        except Exception as exception:
            raise RuntimeError(
                "failed to get DVD device\t: {}".format(exception)
            )
        return device

    @staticmethod
    def _get_dev_sr():
        """Get DVD device(s).

        :returns: DVD device(s)
        :rtype: list
        """
        try:
            device_files = "/dev"
            devices = []
            for filename in os.listdir(device_files):
                if filename.startswith("sr"):
                    devices.append("{}/{}".format(device_files, filename))
        except Exception as exception:
            raise RuntimeError(
                "failed to get DVD device(s)\t: {}".format(exception)
            )
        return devices

    def get_titles(self):
        """Get titles.

        :returns: titles
        :rtype: dict
        """
        try:
            title = re.compile("Title: ([0-9]+), ")
            titles = {}
            process = subprocess.Popen(
                ["lsdvd", self.device], stdout=subprocess.PIPE
            )
            for line in process.stdout.readlines():
                line = line.decode()
                match = title.match(line)
                if match:
                    unpadded = re.compile("[1-9][0-9]*")
                    number = unpadded.findall(match.group(1))[0].zfill(2)
                    name = "title{}".format(number)
                    titles[number] = {"name": name, "info": line}
        except Exception as exception:
            raise RuntimeError(
                "failed to get titles\t: {}".format(exception)
            )
        return titles

    def rip(self, titles):
        """Rip titles.

        :param list titles: list of titles
        """
        try:
            for title in titles:
                args = [
                    "mplayer",
                    self.PATH.format(self.device, title)
                    "-v",
                    "-dumpstream",
                    "-dumpfile", self.DUMPFILE.format(title)
                ]
                subprocess.Popen(args)
                fp = open(self.CHAPTERINFO.format(self.title))
                args = [
                    "dvdxchap",
                    "-t", title,
                    self.device,
                ]
                subprocess.Popen(args, stdout=fp)
        except Exception:
            raise RuntimeError(
                "failed to rip titles\t: {}".format(exception)
            )
        finally:
            fp.close()
        return
