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


# third party imports
try:
    import notify2

    def init(name):
        """
        Initialise notifications under the given name
        """
        notify2.init(name)

    def send(summary, message="", icon=""):
        notification = notify2.Notification(summary, message, icon)
        notification.show()
except ImportError:
    def init(name):
        pass

    def send(*args, **kwargs):
        pass
