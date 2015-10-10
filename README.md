# SUDO Controls
SUDO Controls is a light-weight **SUDO fragments/rules** distribution & management framework which:

* uses a **desired state** model: SUDO Controls pushes fragments from a master (or slave) server onto client host(s) and applies them according to the central configuration.

* uses **SSH** as **transport** mechanism: SUDO Controls connects to client hosts through the secure path of SSH.

* supports a **Master→Slave→Client** model so that information can be propagated within more complex LAN set-ups.

* performs operations with **least privileges**: copy/distribute operations are performed with a low-privileged account. Only the actual snippet updates requires super-user privileges.

* uses a **two-stage** approach to activate **SUDO fragments**: copy (or distribute) and apply. Fragments are first copied into a temporary location on each client hosts - the holding directory - and not applied automatically. Applying or activating fragments on a client host is a separate operation which can be triggered either locally or remotely (from the SUDO master)

* allows the use of (nested) **groups** in the master configuration: fragments and hosts can be grouped in the SUDO master configuration files to allow a simplified configuration. Nesting of groups is allowed up to one level deep.

* can discover SSH host public keys to (re)create `known_hosts` file(s) for a large amount of hosts

* requires **no client agent** component and is **stateless**: SUDO Controls performs operations by pushing fragments or commands to client hosts. Update processes on the client hosts will only be started on-demand. If the SUDO master is - for whatever reason - unavailable then active fragments on a client host remain in place.

* is **easy** to **configure** and **maintain** (command-line based): the configuration is stored in a limited number of flat files and be easily updated. A very rudimentary syntax checking facility is also available to check the consistency of the most important (master) configuration files.

More documentation can be found at http://www.kudos.be/Projects/SUDO_Controls.html
