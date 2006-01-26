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

#include <fstream>

#include <boost/format.hpp>

using boost::format;
using namespace sbuild;

keyfile::keyfile():
  groups(),
  separator(',')
{
}

keyfile::keyfile(std::string const& file):
  groups(),
  separator(',')
{
  std::ifstream fs(file.c_str());
  if (fs)
    {
      fs.imbue(std::locale("C"));
      fs >> *this;
    }
  else
    {
      format fmt(_("Can't open configuration file %1%"));
      fmt % file;
      throw error(fmt);
    }
}

keyfile::keyfile(std::istream& stream):
  groups(),
  separator(',')
{
  stream >> *this;
}

keyfile::~keyfile()
{
}

string_list
keyfile::get_groups() const
{
  string_list ret;

  for (group_map_type::const_iterator pos = this->groups.begin();
       pos != this->groups.end();
       ++pos)
    ret.push_back(pos->first);

  return ret;
}

string_list
keyfile::get_keys(std::string const& group) const
{
  string_list ret;

  const group_type *found_group = find_group(group);
  if (found_group)
    {
      item_map_type const& items(std::tr1::get<1>(*found_group));
      for (item_map_type::const_iterator pos = items.begin();
	   pos != items.end();
	   ++pos)
	ret.push_back(pos->first);
    }

  return ret;
}

bool
keyfile::has_group(std::string const& group) const
{
  return (find_group(group) != 0);
}

bool
keyfile::has_key(std::string const& group,
		 std::string const& key) const
{
  return (find_item(group, key) != 0);
}

void
keyfile::remove_group(std::string const& group)
{
  group_map_type::iterator pos = this->groups.find(group);
  if (pos != this->groups.end())
    this->groups.erase(pos);
}

void
keyfile::remove_key(std::string const& group,
		    std::string const& key)
{
  group_type *found_group = find_group(group);
  if (found_group)
    {
      item_map_type& items = std::tr1::get<1>(*found_group);
      item_map_type::iterator pos = items.find(key);
      if (pos != items.end())
	items.erase(pos);
    }
}

const keyfile::group_type *
keyfile::find_group(std::string const& group) const
{
  group_map_type::const_iterator pos = this->groups.find(group);
  if (pos != this->groups.end())
    return &pos->second;

  return 0;
}

keyfile::group_type *
keyfile::find_group(std::string const& group)
{
  group_map_type::iterator pos = this->groups.find(group);
  if (pos != this->groups.end())
    return &pos->second;

  return 0;
}

const keyfile::item_type *
keyfile::find_item(std::string const& group,
		   std::string const& key) const
{
  const group_type *found_group = find_group(group);
  if (found_group)
    {
      item_map_type const& items = std::tr1::get<1>(*found_group);
      item_map_type::const_iterator pos = items.find(key);
      if (pos != items.end())
	return &pos->second;
    }

  return 0;
}

keyfile::item_type *
keyfile::find_item(std::string const& group,
		   std::string const& key)
{
  group_type *found_group = find_group(group);
  if (found_group)
    {
      item_map_type& items = std::tr1::get<1>(*found_group);
      item_map_type::iterator pos = items.find(key);
      if (pos != items.end())
	return &pos->second;
    }

  return 0;
}

void
keyfile::print_comment(std::string const& comment,
		       std::ostream&      stream)
{
  std::string::size_type last_pos = 0;
  std::string::size_type pos = comment.find_first_of('\n', last_pos);

  while (pos !=std::string::npos || last_pos != std::string::npos)
    {
      stream << '#' << comment.substr(last_pos, pos - last_pos);
      // Find next
      last_pos = comment.find_first_not_of('\n', pos);
      pos = comment.find_first_of('\n', last_pos);
    }
}

void
keyfile::check_priority (std::string const& group,
			 std::string const& key,
			 priority priority,
			 bool     valid) const
{
  if (valid == false)
    {
      switch (priority)
	{
	case PRIORITY_REQUIRED:
	  log_error()
	    << boost::format(_("%1% chroot: A required parameter \"%2%\" is missing."))
	    % group % key
	    << std::endl;
	  break;
	default:
	  break;
	}
    }
  else
    {
      switch (priority)
	{
	case PRIORITY_DEPRECATED:
	  log_warning()
	    << boost::format(_("%1% chroot: A deprecated parameter \"%2%\" has been specified."))
	    % group % key
	    << std::endl;
	  log_info()
	    << _("This option will be removed in the future.") << std::endl;
	  break;
	case PRIORITY_OBSOLETE:
	  log_warning()
	    << boost::format(_("%1% chroot: An obsolete parameter \"%2%\" has been specified."))
	    % group % key
	    << std::endl;
	  log_info()
	    << _("This option has been removed, and no longer has any effect.") << std::endl;
	case PRIORITY_DISALLOWED:
	  log_error()
	    << boost::format(_("%1% chroot: A disallowed parameter \"%2%\" has been specified."))
	    % group % key
	    << std::endl;
	  log_info()
	    << _("This option is not allowed in this context.") << std::endl;
	  break;
	    default:
	      break;
	}
    }
}

/*
 * Local Variables:
 * mode:C++
 * End:
 */
