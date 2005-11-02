/* sbuild-config - sbuild config object
 *
 * Copyright © 2005  Roger Leigh <rleigh@debian.org>
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

/**
 * SECTION:sbuild-config
 * @short_description: config object
 * @title: SbuildConfig
 *
 * This class holds the configuration details from the configuration
 * file.  Conceptually, it's an opaque container of #SbuildChroot
 * objects.
 *
 * Methods are provided to query the available chroots and find
 * specific chroots.
 */

#include <config.h>

#define _GNU_SOURCE
#include <errno.h>
#include <stdlib.h>
#include <string.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <dirent.h>
#include <fcntl.h>
#include <unistd.h>

#include <glib.h>
#include <glib/gi18n.h>

#include "sbuild-config.h"
#include "sbuild-lock.h"

/**
 * sbuild_config_file_error_quark:
 *
 * Get the SBUILD_CONFIG_FILE_ERROR domain number.
 *
 * Returns the domain.
 */
GQuark
sbuild_config_file_error_quark (void)
{
  static GQuark error_quark = 0;

  if (error_quark == 0)
    error_quark = g_quark_from_static_string ("sbuild-config-file-error-quark");

  return error_quark;
}

enum
{
  PROP_0,
  PROP_CONFIG_FILE,
  PROP_CONFIG_DIR
};

static GObjectClass *parent_class;

G_DEFINE_TYPE(SbuildConfig, sbuild_config, G_TYPE_OBJECT)

/**
 * sbuild_config_new:
 *
 * Creates a new #SbuildConfig.
 *
 * Returns the newly created #SbuildConfig.
 */
SbuildConfig *
sbuild_config_new (void)
{
  return (SbuildConfig *) g_object_new (SBUILD_TYPE_CONFIG, NULL);
}

/**
 * sbuild_config_new_from_file:
 * @file: the filename to open.
 *
 * Creates a new #SbuildConfig.
 *
 * Returns the newly created #SbuildConfig.
 */
SbuildConfig *
sbuild_config_new_from_file (const char *file)
{
  return (SbuildConfig *) g_object_new (SBUILD_TYPE_CONFIG,
					"config-file", file,
					NULL);
}

/**
 * sbuild_config_new_from_directory:
 * @dir: the directory to open.
 *
 * Creates a new #SbuildConfig from a directory of files.
 *
 * Returns the newly created #SbuildConfig.
 */
SbuildConfig *
sbuild_config_new_from_directory (const char *dir)
{
  return (SbuildConfig *) g_object_new (SBUILD_TYPE_CONFIG,
					"config-directory", dir,
					NULL);
}

/**
 * sbuild_config_check_security:
 * @fd: the file descriptor to check.
 * @error: the #GError to report errors.
 *
 * Check the permissions and ownership of the configuration file.  The
 * file must be owned by root, not writable by other, and be a regular
 * file.
 *
 * Returns TRUE if the checks succeed, FALSE on failure.
 */
static gboolean
sbuild_config_check_security(int      fd,
			     GError **error)
{
  struct stat statbuf;
  if (fstat(fd, &statbuf) < 0)
    {
      g_set_error(error,
		  SBUILD_CONFIG_FILE_ERROR, SBUILD_CONFIG_FILE_ERROR_STAT_FAIL,
		  _("failed to stat file: %s"), g_strerror(errno));
      return FALSE;
    }

  if (statbuf.st_uid != 0)
    {
      g_set_error(error,
		  SBUILD_CONFIG_FILE_ERROR, SBUILD_CONFIG_FILE_ERROR_OWNERSHIP,
		  _("not owned by user root"));
      return FALSE;
    }

  if (statbuf.st_mode & S_IWOTH)
    {
      g_set_error(error,
		  SBUILD_CONFIG_FILE_ERROR, SBUILD_CONFIG_FILE_ERROR_PERMISSIONS,
		  _("others have write permission"));
      return FALSE;
    }

  if (!S_ISREG(statbuf.st_mode))
    {
      g_set_error(error,
		  SBUILD_CONFIG_FILE_ERROR, SBUILD_CONFIG_FILE_ERROR_NOT_REGULAR,
		  _("not a regular file"));
      return FALSE;
    }

  return TRUE;
}

/**
 * sbuild_config_load:
 * @file: the file to load.
 * @list: a list to append the #SbuildChroot objects to.
 *
 * Load a configuration file.  If there are problems with the
 * configuration file, the program will be aborted immediately.
 */
void
sbuild_config_load (const char  *file,
		    GList      **list)
{

  /* Use a UNIX fd, for security (no races) */
  int fd = open(file, O_RDONLY|O_NOFOLLOW);
  if (fd < 0)
    {
      g_printerr(_("%s: failed to load configuration: %s\n"), file, g_strerror(errno));
      exit (EXIT_FAILURE);
    }

  GError *lock_error = NULL;
  sbuild_lock_set_lock(fd, SBUILD_LOCK_SHARED, 2, &lock_error);
  if (lock_error)
    {
      g_printerr(_("%s: lock acquisition failure: %s\n"), file, lock_error->message);
      exit (EXIT_FAILURE);
    }

  GError *security_error = NULL;
  sbuild_config_check_security(fd, &security_error);
  if (security_error)
    {
      g_printerr(_("%s: security failure: %s\n"), file, security_error->message);
      exit (EXIT_FAILURE);
    }

  /* Now create an IO Channel and read in the data */
  GIOChannel *channel = g_io_channel_unix_new(fd);
  gchar *data = NULL;
  gsize size = 0;
  GError *read_error = NULL;

  g_io_channel_set_encoding(channel, NULL, NULL);
  g_io_channel_read_to_end(channel, &data, &size, &read_error);
  if (read_error)
    {
      g_printerr(_("%s: read failure: %s\n"), file, read_error->message);
      exit (EXIT_FAILURE);
    }

  GError *unlock_error = NULL;
  sbuild_lock_unset_lock(fd, &unlock_error);
  if (unlock_error)
    {
      g_printerr(_("%s: lock discard failure: %s\n"), file, unlock_error->message);
      exit (EXIT_FAILURE);
    }

  GError *close_error = NULL;
  g_io_channel_shutdown(channel, FALSE, &close_error);
  if (close_error)
    {
      g_printerr(_("%s: close failure: %s\n"), file, close_error->message);
      exit (EXIT_FAILURE);
    }
  g_io_channel_unref(channel);

  /* Create key file */
  GKeyFile *keyfile = g_key_file_new();
  g_key_file_set_list_separator(keyfile, ',');
  GError *parse_error = NULL;
  g_key_file_load_from_data(keyfile, data, size, G_KEY_FILE_NONE, &parse_error);
  g_free(data);
  data = NULL;

  if (parse_error)
    {
      g_printerr(_("%s: parse failure: %s\n"), file, parse_error->message);
      exit (EXIT_FAILURE);
    }

  /* Create SbuildChroot objects from key file */
  char **groups = g_key_file_get_groups(keyfile, NULL);
  for (guint i=0; groups[i] != NULL; ++i)
    {
      SbuildChroot *chroot = sbuild_chroot_new_from_keyfile(keyfile, groups[i]);
      if (chroot)
	*list = g_list_append(*list, chroot);
    }
  g_strfreev(groups);
  g_key_file_free(keyfile);
}

/**
 * sbuild_config_add_config_file:
 * @config: an #SbuildConfig.
 * @file: the filename to add.
 *
 * Add the configuration filename.  The configuration file specified
 * will be loaded.
 */
void
sbuild_config_add_config_file (SbuildConfig *config,
			       const char   *file)
{
  g_return_if_fail(SBUILD_IS_CONFIG(config));

  if (file == NULL || strlen(file) == 0)
    return;

  sbuild_config_load(file, &config->chroots);

  g_object_notify(G_OBJECT(config), "config-file");
}

/**
 * sbuild_config_add_config_directory:
 * @config: an #SbuildConfig.
 * @dir: the directory to add.
 *
 * Add the configuration directory.  The configuration files in the
 * directory will be loaded.
 */
void
sbuild_config_add_config_directory (SbuildConfig *config,
				    const char   *dir)
{
  g_return_if_fail(SBUILD_IS_CONFIG(config));

  if (dir == NULL || strlen(dir) == 0)
    return;

  DIR *d = opendir(dir);
  if (d == NULL)
    {
      g_printerr(_("%s: failed to open directory: %s\n"), d, g_strerror(errno));
      exit (EXIT_FAILURE);
    }

  struct dirent *de = NULL;
  while ((de = readdir(d)) != NULL)
    {
      char *filename = g_strconcat(dir, "/", &de->d_name[0], NULL);

      struct stat statbuf;
      if (stat(filename, &statbuf) < 0)
	{
	  g_printerr(_("%s: failed to stat file: %s"), filename, g_strerror(errno));
	  g_free(filename);
	  continue;
	}

      if (!S_ISREG(statbuf.st_mode))
	{
	  if (!(strcmp(de->d_name, ".") == 0 ||
		strcmp(de->d_name, "..") == 0))
	    g_printerr(_("%s: failed to stat file: %s"), filename, g_strerror(errno));
	  g_free(filename);
	  continue;
	}

      sbuild_config_load(filename, &config->chroots);
      g_free(filename);
    }

  g_object_notify(G_OBJECT(config), "config-directory");
}

/**
 * sbuild_config_clear_chroot_list:
 * @list: a pointer to a pointer to a #GList
 *
 * Clear chroot list.
 */
static inline void
sbuild_config_clear_chroot_list (GList **list)
{
  if (*list)
    {
      g_list_foreach(*list, (GFunc) g_object_unref, NULL);
      g_list_free(*list);
      *list = NULL;
    }
}

/**
 * sbuild_config_clear:
 * @config: a #SbuildConfig
 *
 * Clear available chroots.  All loaded chroot configuration details
 * are cleared.
 */
void
sbuild_config_clear (SbuildConfig *config)
{
  g_return_if_fail(SBUILD_IS_CONFIG(config));

  sbuild_config_clear_chroot_list(&config->chroots);
}

/**
 * sbuild_config_get_chroots:
 * @config: a #SbuildConfig
 *
 * Get a list of available chroots.
 *
 * Returns a list of available chroots, or NULL if no chroots are
 * available.
 */
const GList *
sbuild_config_get_chroots (SbuildConfig *config)
{
  g_return_val_if_fail(SBUILD_IS_CONFIG(config), NULL);

  return config->chroots;
}

/**
 * sbuild_config_find_generic:
 * @config: a #SbuildConfig
 * @name: the chroot name to find
 * @func: the comparison function to use
 *
 * Find a chroot by name using the supplied comparison function.
 *
 * Returns the chroot on success, or NULL if the chroot was not found.
 */
static SbuildChroot *
sbuild_config_find_generic (SbuildConfig *config,
			    const char   *name,
			    GCompareFunc  func)
{
  g_return_val_if_fail(SBUILD_IS_CONFIG(config), NULL);

  if (config->chroots)
    {
      SbuildChroot *example = sbuild_chroot_new();
      sbuild_chroot_set_name(example, name);

      GList *elem = g_list_find_custom(config->chroots, example, (GCompareFunc) func);

      g_object_unref(example);
      example = NULL;

      if (elem)
	return (SbuildChroot *) elem->data;
    }

  return NULL;
}

/**
 * chroot_findfunc:
 * @a: an #SbuildChroot
 * @b: an #SbuildChroot
 *
 * Compare the names of the chroots.
 *
 * Return TRUE if the names are the same, otherwise FALSE.
 */
static gint
chroot_findfunc (SbuildChroot *a,
		 SbuildChroot *b)
{
  g_return_val_if_fail(SBUILD_IS_CHROOT(a), FALSE);
  g_return_val_if_fail(SBUILD_IS_CHROOT(b), FALSE);

  if (sbuild_chroot_get_name(a) == NULL ||
      sbuild_chroot_get_name(b) == NULL)
    return FALSE;

  return strcmp(sbuild_chroot_get_name(a),
		sbuild_chroot_get_name(b));
}

/**
 * sbuild_config_find_chroot:
 * @config: an #SbuildConfig
 * @name: the chroot name
 *
 * Find a chroot by its name.
 *
 * Returns the chroot if found, otherwise NULL.
 */
SbuildChroot *
sbuild_config_find_chroot (SbuildConfig *config,
			   const char   *name)
{
  g_return_val_if_fail(SBUILD_IS_CONFIG(config), NULL);

  return sbuild_config_find_generic(config, name, (GCompareFunc) chroot_findfunc);
}

/**
 * alias_findfunc:
 * @a: a #SbuildChroot
 * @b: a #SbuildChroot
 *
 * Compare the aliases of @a with the name of @b.
 *
 * Return TRUE if one of the aliases matches the name, otherwise FALSE.
 */
static gint
alias_findfunc (SbuildChroot *a,
		SbuildChroot *b)
{
  g_return_val_if_fail(SBUILD_IS_CHROOT(a), FALSE);
  g_return_val_if_fail(SBUILD_IS_CHROOT(b), FALSE);

  if (sbuild_chroot_get_name(a) == NULL ||
      sbuild_chroot_get_name(b) == NULL)
    return FALSE;

  gchar **aliases = sbuild_chroot_get_aliases(a);
  if (aliases)
    {
      for (guint i = 0; aliases[i] != NULL; ++i)
	{
	  if (strcmp(aliases[i], sbuild_chroot_get_name(b)) == 0)
	    return 0;
	}
    }
  return 1;
}


/**
 * sbuild_config_find_alias:
 * @config: an #SbuildConfig
 * @name: the chroot name
 *
 * Find a chroot by its name or an alias.
 *
 * Returns the chroot if found, otherwise NULL.
 */
SbuildChroot *
sbuild_config_find_alias (SbuildConfig *config,
			  const char   *name)
{
  g_return_val_if_fail(SBUILD_IS_CONFIG(config), NULL);

  SbuildChroot *chroot = sbuild_config_find_chroot(config, name);
  if (chroot == NULL)
    chroot = sbuild_config_find_generic(config, name, (GCompareFunc) alias_findfunc);
  return chroot;
}

/**
 * sbuild_config_get_chroot_list_foreach:
 * @chroot: an #SbuildChroot
 * @list: the list to append the names to
 *
 * Add the name and aliases of a chroot to @list.
 */
static void
sbuild_config_get_chroot_list_foreach (SbuildChroot  *chroot,
				       GList        **list)
{
  g_return_if_fail(SBUILD_IS_CHROOT(chroot));

  if (sbuild_chroot_get_name(chroot) == NULL)
    return;

  *list = g_list_append(*list, (gpointer) sbuild_chroot_get_name(chroot));

  gchar **aliases = sbuild_chroot_get_aliases(chroot);
  if (aliases)
    {
      for (guint i = 0; aliases[i] != NULL; ++i)
	*list = g_list_append(*list, aliases[i]);
    }
}

/**
 * sbuild_config_get_chroot_list:
 * @config: an #SbuildConfig
 *
 * Get the names (including aliases) of all the available chroots.
 *
 * Returns the list, or NULL if no chroots are available.
 */
GList *
sbuild_config_get_chroot_list (SbuildConfig *config)
{
  g_return_val_if_fail(SBUILD_IS_CONFIG(config), NULL);

  if (config->chroots)
    {
      GList *list = NULL;

      g_list_foreach(config->chroots, (GFunc) sbuild_config_get_chroot_list_foreach, &list);
      list = g_list_sort(list, (GCompareFunc) strcmp);
      return list;
    }

  return NULL;
}

/**
 * sbuild_config_print_chroot_list_foreach:
 * @name: the name to print
 * @file: the file to print to
 *
 * Print a chroot name to the specified file.
 */
static void
sbuild_config_print_chroot_list_foreach (const char *name,
					 FILE       *file)
{
  g_print("%s\n", name);
}

/**
 * sbuild_config_print_chroot_list:
 * @config: an #SbuildConfig
 * @file: the file to print to
 *
 * Print all the available chroots to the specified file.
 */
void
sbuild_config_print_chroot_list (SbuildConfig *config,
				 FILE         *file)
{
  g_return_if_fail(SBUILD_IS_CONFIG(config));

  GList *list = sbuild_config_get_chroot_list(config);
  if (list != NULL)
    {
      g_list_foreach(list, (GFunc) sbuild_config_print_chroot_list_foreach, file);
      g_list_free(list);
    }
}

/**
 * sbuild_config_print_chroot_info:
 * @config: an #SbuildConfig
 * @chroots: the chroots to print
 * @file: the file to print to
 *
 * Print information about the specified chroots to the specified
 * file.
 */
void
sbuild_config_print_chroot_info (SbuildConfig  *config,
				 char         **chroots,
				 FILE          *file)
{
  g_return_if_fail(SBUILD_IS_CONFIG(config));

  for (guint i=0; chroots[i] != NULL; ++i)
    {
      SbuildChroot *chroot = sbuild_config_find_alias(config, chroots[i]);
      if (chroot)
	{
	  sbuild_chroot_print_details(chroot, stdout);
	  if (chroots[i+1] != NULL)
	    g_fprintf(stdout, "\n");
	}
      else
	g_printerr(_("%s: No such chroot\n"), chroots[i]);
    }
}

/**
 * sbuild_config_validate_chroots:
 * @config: an #SbuildConfig
 * @chroots: the chroots to validate
 *
 * Check that all the chroots specified by @chroots exist in @config.
 *
 * Returns NULL if all chroots are valid, or else a vector of invalid
 * chroots.
 */
char **
sbuild_config_validate_chroots(SbuildConfig  *config,
			       char         **chroots)
{
  g_return_val_if_fail(SBUILD_IS_CONFIG(config), FALSE);

  GList *invalid_list = NULL;

  for (guint i=0; chroots[i] != NULL; ++i)
    {
      SbuildChroot *chroot = sbuild_config_find_alias(config, chroots[i]);
      if (chroot == NULL)
	{
	  invalid_list = g_list_append(invalid_list, chroots[i]);
	}
    }

  char **return_list = NULL;

  if (invalid_list)
    {
      return_list = g_new(char *, g_list_length(invalid_list) + 1);

      GList *iter = invalid_list;
      for (guint i = 0; iter != NULL; iter = g_list_next(iter), ++i)
	return_list[i] = g_strdup((const char *) iter->data);
      return_list[g_list_length(invalid_list)] = NULL;

      g_list_free(invalid_list);
    }

  return return_list;
}

static void
sbuild_config_init (SbuildConfig *config)
{
  g_return_if_fail(SBUILD_IS_CONFIG(config));

  config->chroots = NULL;
}

static void
sbuild_config_finalize (SbuildConfig *config)
{
  g_return_if_fail(SBUILD_IS_CONFIG(config));

  sbuild_config_clear_chroot_list(&config->chroots);

  if (parent_class->finalize)
    parent_class->finalize(G_OBJECT(config));
}

static void
sbuild_config_set_property (GObject      *object,
			    guint         param_id,
			    const GValue *value,
			    GParamSpec   *pspec)
{
  SbuildConfig *config;

  g_return_if_fail (object != NULL);
  g_return_if_fail (SBUILD_IS_CONFIG (object));

  config = SBUILD_CONFIG(object);

  switch (param_id)
    {
    case PROP_CONFIG_FILE:
      sbuild_config_add_config_file(config, g_value_get_string(value));
      break;
    case PROP_CONFIG_DIR:
      sbuild_config_add_config_directory(config, g_value_get_string(value));
      break;
    default:
      G_OBJECT_WARN_INVALID_PROPERTY_ID (object, param_id, pspec);
      break;
    }
}

static void
sbuild_config_get_property (GObject    *object,
			    guint       param_id,
			    GValue     *value,
			    GParamSpec *pspec)
{
  SbuildConfig *config;

  g_return_if_fail (object != NULL);
  g_return_if_fail (SBUILD_IS_CONFIG (object));

  config = SBUILD_CONFIG(object);

  switch (param_id)
    {
    default:
      G_OBJECT_WARN_INVALID_PROPERTY_ID (object, param_id, pspec);
      break;
    }
}

static void
sbuild_config_class_init (SbuildConfigClass *klass)
{
  GObjectClass *gobject_class = G_OBJECT_CLASS (klass);
  parent_class = g_type_class_peek_parent (klass);

  gobject_class->finalize = (GObjectFinalizeFunc) sbuild_config_finalize;
  gobject_class->set_property = (GObjectSetPropertyFunc) sbuild_config_set_property;
  gobject_class->get_property = (GObjectGetPropertyFunc) sbuild_config_get_property;

  g_object_class_install_property
    (gobject_class,
     PROP_CONFIG_FILE,
     g_param_spec_string ("config-file", "Configuration File",
			  "The file containing the chroot configuration",
			  "",
			  (G_PARAM_WRITABLE | G_PARAM_CONSTRUCT)));

  g_object_class_install_property
    (gobject_class,
     PROP_CONFIG_DIR,
     g_param_spec_string ("config-directory", "Configuration Directory",
			  "The directory containing the chroot configuration files",
			  "",
			  (G_PARAM_WRITABLE | G_PARAM_CONSTRUCT)));
}

/*
 * Local Variables:
 * mode:C
 * End:
 */
