{%- from "nginx/map.jinja" import server with context %}
{%- if server.enabled %}

include:
  - nginx.server.users
  - nginx.server.sites

{#- Do not start nginx when installing packages #}
{%- if grains.os_family == "Debian" %}
policy-rc.d_present:
  file.managed:
  - name: /usr/sbin/policy-rc.d
  - mode: 755
  - contents: |
      #!/bin/sh
      exit 101
  - require_in:
    - nginx_packages
{%- endif %}

nginx_packages:
  pkg.installed:
  - names: {{ server.pkgs }}

{%- if server.get('extras', False) %}
nginx_extra_packages:
  pkg.installed:
  - name: nginx-extras
  - require:
    - nginx_packages
{%- endif %}

{#- Do not start nginx when installing packages #}
{%- if grains.os_family == "Debian" %}
policy-rc.d_absent:
  file.absent:
  - name: /usr/sbin/policy-rc.d
  - require:
    - nginx_packages
{%- endif %}

/etc/nginx/conf.d/default.conf:
  file.absent:
  - require:
    - pkg: nginx_packages

/etc/nginx/sites-enabled/default:
  file.absent:
  - require:
    - pkg: nginx_packages

/etc/nginx/sites-available/default:
  file.absent:
  - require:
    - pkg: nginx_packages

/etc/nginx/nginx.conf:
  file.managed:
  - source: salt://nginx/files/nginx.conf
  - template: jinja
  - require:
    - pkg: nginx_packages
  - watch_in:
    - module: nginx_config_test

{%- if not salt['file.directory_exists']('/etc/ssl/private') %}
/etc/ssl/private:
  file.directory:
  - mode: 0710
  - user: root
  - group: root
  - makedirs: true
  - require:
    - pkg: nginx_packages
{%- else %}
/etc/ssl/private:
  file.directory:
  - require:
    - pkg: nginx_packages
{%- endif %}

{%- if server.stream is defined %}
/etc/nginx/stream.conf:
  file.managed:
  - source: salt://nginx/files/stream.conf
  - template: jinja
  - require:
    - pkg: nginx_packages
  - watch_in:
    - module: nginx_config_test
{%- endif %}

{%- if server.upstream is defined %}
/etc/nginx/upstream.conf:
  file.managed:
  - source: salt://nginx/files/upstream.conf
  - template: jinja
  - require:
    - pkg: nginx_packages
  - watch_in:
    - module: nginx_config_test
{%- endif %}

{%- if server.certificates is defined %}
{%- for cert in server.certificates %}
/etc/nginx/certificates/{{ cert }}.pem:
  file.managed:
  - contents_pillar: "nginx:server:certificates:{{ cert }}"
  - require:
    - pkg: nginx_packages
  - watch_in:
    - module: nginx_config_test
  - makedirs: True
{%- endfor %}
{%- endif %}


nginx_service:
  service.running:
  - name: {{ server.service }}
  - reload: True
  - require:
    - pkg: nginx_packages
  - watch:
    - module: nginx_config_test

nginx_config_test:
  module.wait:
    - name: nginx.configtest

{%- set generate_dhparams = { 'enabled': False } %}
{%- for site_name, site in server.get('site', {}).items() %}
{%- if site.get('ssl', {}).get('enabled') and site.ssl.get('mode', 'secure') == 'secure' %}
  {%- do generate_dhparams.update({ 'enabled': True }) %}
  {%- break %}
{%- endif %}
{%- endfor %}

{%- if generate_dhparams['enabled'] %}
nginx_generate_dhparams:
  cmd.run:
  - name: openssl dhparam -out /etc/ssl/dhparams.pem 2048
  - creates: /etc/ssl/dhparams.pem
  - require:
    - pkg: nginx_packages
  - watch_in:
    - module: nginx_config_test
{%- endif %}

{%- if server.wait_for_service is defined %}

{%- if salt['test.provider']('service') == 'systemd' %}

/etc/systemd/system/nginx.service.d:
  file.directory:
  - mode: 0755
  - user: root
  - group: root
  - require:
    - pkg: nginx_packages

/etc/systemd/system/nginx.service.d/override.conf:
  file.managed:
  - source: salt://nginx/files/service.override.conf
  - template: jinja
  - require:
    - file: /etc/systemd/system/nginx.service.d

systemctl_reload:
  module.run:
  - name: service.systemctl_reload
  - onchanges:
    - file: /etc/systemd/system/nginx.service.d/override.conf
  - watch_in:
    - module: nginx_config_test

{%- endif %}

{%- endif %}

{%- if server.get('periodic_reload', False) %}
# Periodic config reload (e.g. for refreshing updated certificates)
nginx_periodic_reload:
  cron.present:
    - name: "nginx -s reload"
    - user: root
    - special: '@daily'
{%- endif %}

{%- endif %}
