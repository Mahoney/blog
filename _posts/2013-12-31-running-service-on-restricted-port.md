---
layout: post
title: Running a service on a restricted port using IP Tables
date: '2013-12-31T12:16:00.001Z'
author: Robert Elliot
tags:
modified_time: '2013-12-31T15:38:08.506Z'
blogger_id: tag:blogger.com,1999:blog-8805447266344101474.post-7017780621784475519
blogger_orig_url: http://blog.lidalia.org.uk/2013/12/running-service-on-restricted-port.html
---

Common problem - you need to run up a service (e.g. an HTTP server) on a port <=
1024 (e.g. port 80). You don't want to run it as root, because you're not *that*
stupid. You don't want to run some quite complicated other thing you might
misconfigure and whose features you don't actually need (I'm looking at you,
Apache HTTPD) as a proxy just to achieve this end. What to do?

Well, you can run up your service on an unrestricted port like 8080 as a user
with restricted privileges, and then do NAT via IP Tables to redirect TCP
traffic from a restricted port (e.g. 80) to that unrestricted one:

```bash
iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-ports 8080
```

However, this isn't quite complete - if you are on the host itself this rule
will not apply, so you still can't get to the service on the restricted port. To
work around this I have so far found you need to add an OUTPUT rule. As it's an
OUTPUT rule it *must* be restricted to only the IP address of the local box -
otherwise you'll find requests apparently to other servers are being re-routed
to localhost on the unrestricted port. For the loopback adapter this looks like
this:

```bash
iptables -t nat -A OUTPUT -p tcp -d 127.0.0.1 --dport 80 -j REDIRECT --to-ports 8080
```

If you want a comprehensive solution, you'll have to add the same rule over and
over for the IP addresses of all network adapters on the host. This can be done
in Puppet as so:

```puppet
define localiptablesredirect($to_port) {
  $local_ip_and_from_port = split($name,'-')
  $local_ip = $local_ip_and_from_port[0]
  $from_port = $local_ip_and_from_port[1]

  exec { "iptables-redirect-localport-${local_ip}-${from_port}":
    command => "/sbin/iptables -t nat -A OUTPUT -p tcp -d ${local_ip} --dport ${from_port} -j REDIRECT --to-ports ${to_port}; service iptables save",
    user    => 'root',
    group   => 'root',
    unless  => "/sbin/iptables -S -t nat | grep -q 'OUTPUT -d ${local_ip}/32 -p tcp -m tcp --dport ${from_port} -j REDIRECT --to-ports ${to_port}' 2>/dev/null"
  }
}

define iptablesredirect($to_port) {
  $from_port = $name
  if ($from_port != $to_port) {
    exec { "iptables-redirect-port-${from_port}":
      command => "/sbin/iptables -t nat -A PREROUTING -p tcp --dport ${from_port} -j REDIRECT --to-ports ${to_port}; service iptables save",
      user    => 'root',
      group   => 'root',
      unless  => "/sbin/iptables -S -t nat | grep -q 'PREROUTING -p tcp -m tcp --dport ${from_port} -j REDIRECT --to-ports ${to_port}' 2>/dev/null";
    }

    $interface_names = split($::interfaces, ',')
    $interface_addresses_and_incoming_port = inline_template('<%= @interface_names.map{ |interface_name| scope.lookupvar("ipaddress_#{interface_name}") }.reject{ |ipaddress| ipaddress == :undefined }.uniq.map{ |ipaddress| "#{ipaddress}-#{incoming_port}" }.join(" ") %>')
    $interface_addr_and_incoming_port_array = split($interface_addresses_and_incoming_port, ' ')

    localiptablesredirect { $interface_addr_and_incoming_port_array:
      to_port    => $to_port
    }
  }
}

iptablesredirect { '80':
  to_port    => 8080
}
```
