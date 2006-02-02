/* Copyright © 2005-2006  Roger Leigh <rleigh@debian.org>
 *
 * schroot is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * schroot is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston,
 * MA  02111-1307  USA
 *
 *********************************************************************/

#include <config.h>

#include "sbuild.h"

#include <cerrno>
#include <iostream>

#include <sys/types.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <unistd.h>

#include <boost/format.hpp>

using std::endl;
using boost::format;
using namespace sbuild;

ChrootLvmSnapshot::ChrootLvmSnapshot():
  ChrootBlockDevice(),
  snapshot_device(),
  snapshot_options()
{
}

ChrootLvmSnapshot::ChrootLvmSnapshot (keyfile const&     keyfile,
				      std::string const& group):
  ChrootBlockDevice(keyfile, group),
  snapshot_device(),
  snapshot_options()
{
}

ChrootLvmSnapshot::~ChrootLvmSnapshot()
{
}

Chroot::chroot_ptr
ChrootLvmSnapshot::clone () const
{
  return chroot_ptr(new ChrootLvmSnapshot(*this));
}

std::string const&
ChrootLvmSnapshot::get_snapshot_device () const
{
  return this->snapshot_device;
}

void
ChrootLvmSnapshot::set_snapshot_device (std::string const& snapshot_device)
{
  this->snapshot_device = snapshot_device;
}

std::string const&
ChrootLvmSnapshot::get_mount_device () const
{
  return this->snapshot_device;
}

std::string const&
ChrootLvmSnapshot::get_snapshot_options () const
{
  return this->snapshot_options;
}

void
ChrootLvmSnapshot::set_snapshot_options (std::string const& snapshot_options)
{
  this->snapshot_options = snapshot_options;
}

std::string const&
ChrootLvmSnapshot::get_chroot_type () const
{
  static const std::string type("lvm-snapshot");

  return type;
}

void
ChrootLvmSnapshot::setup_env (environment& env)
{
  this->ChrootBlockDevice::setup_env(env);

  env.add("CHROOT_LVM_SNAPSHOT_NAME", sbuild::basename(get_snapshot_device()));
  env.add("CHROOT_LVM_SNAPSHOT_DEVICE", get_snapshot_device());
  env.add("CHROOT_LVM_SNAPSHOT_OPTIONS", get_snapshot_options());
}

void
ChrootLvmSnapshot::setup_lock (SetupType type,
			       bool      lock)
{
  std::string device;
  struct stat statbuf;

  /* Lock is removed by setup script on setup stop.  Unlocking here
     would fail: the LVM snapshot device no longer exists. */
  if (!(type == SETUP_STOP && lock == false))
    {
      if (type == SETUP_START)
	device = get_device();
      else
	device = get_snapshot_device();

      if (device.empty())
	{
	  format fmt(_("%1% chroot: device name not set"));
	  fmt % get_name();
	  throw error(fmt);
	}
      else if (stat(device.c_str(), &statbuf) == -1)
	{
	  format fmt(_("%1% chroot: failed to stat device %2%: %3%"));
	  fmt % get_name() % device % strerror(errno);
	  throw error(fmt);
	}
      else if (!S_ISBLK(statbuf.st_mode))
	{
	  format fmt(_("%1% chroot: %2% is not a block device\n"));
	  fmt % get_name() % device;
	  throw error(fmt);
	}
      else
	{
	  /* Lock is preserved while running a command. */
	  if ((type == RUN_START && lock == false) ||
	      (type == RUN_STOP && lock == true))
	    return;

	  sbuild::DeviceLock dlock(device);
	  if (lock)
	    {
	      try
		{
		  dlock.set_lock(Lock::LOCK_EXCLUSIVE, 15);
		}
	      catch (sbuild::Lock::error const& e)
		{
		  format fmt(_("%1%: failed to lock device: %2%"));
		  fmt % device % e.what();
		  throw error(fmt);
		}
	    }
	  else
	    {
	      try
		{
		  dlock.unset_lock();
		}
	      catch (sbuild::Lock::error const& e)
		{
		  format fmt(_("%1%: failed to unlock device: %2%"));
		  fmt % device % e.what();
		  throw error(fmt);
		}
	    }
	}
    }

  /* Create or unlink session information. */
  if ((type == SETUP_START && lock == true) ||
      (type == SETUP_STOP && lock == false))
    {
      bool start = (type == SETUP_START);
      setup_session_info(start);
    }
}

Chroot::SessionFlags
ChrootLvmSnapshot::get_session_flags () const
{
  return SESSION_CREATE;
}

void
ChrootLvmSnapshot::print_details (std::ostream& stream) const
{
  this->ChrootBlockDevice::print_details(stream);

  if (!this->snapshot_device.empty())
    stream << format_details(_("LVM Snapshot Device"),
			     get_snapshot_device());
  if (!this->snapshot_options.empty())
    stream << format_details(_("LVM Snapshot Options"),
			     get_snapshot_options());
  stream << std::flush;
}

void
ChrootLvmSnapshot::get_keyfile (keyfile& keyfile) const
{
  ChrootBlockDevice::get_keyfile(keyfile);

  keyfile.set_value(get_name(), "lvm-snapshot-device",
		    get_snapshot_device());

  keyfile.set_value(get_name(), "lvm-snapshot-options",
		    get_snapshot_options());
}

void
ChrootLvmSnapshot::set_keyfile (keyfile const& keyfile)
{
  ChrootBlockDevice::set_keyfile(keyfile);

  std::string snapshot_device;
  if (keyfile.get_value(get_name(), "lvm-snapshot-device",
			get_active() ?
			keyfile::PRIORITY_REQUIRED :
			keyfile::PRIORITY_DISALLOWED,
			snapshot_device))
    set_snapshot_device(snapshot_device);

  std::string snapshot_options;
  if (keyfile.get_value(get_name(), "lvm-snapshot-options",
			keyfile::PRIORITY_REQUIRED, snapshot_options))
    set_snapshot_options(snapshot_options);
}

/*
 * Local Variables:
 * mode:C++
 * End:
 */
