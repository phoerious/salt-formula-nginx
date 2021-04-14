{%- from "nginx/map.jinja" import server with context %}

{%- set ssl_certificates = {} %}

{%- for site_name, site in server.get('site', {}).items() %}

{%- set site_type = site.get('type', 'nginx_static') %}

{%- if site.get('enabled') %}

{%- if site.get('ssl', {'enabled': False}).enabled %}
{%- if site.ssl.get('dhparam', {'enabled': False}).enabled %}
nginx_generate_{{ site_name }}_dhparams:
  cmd.run:
  - name: openssl dhparam -out /etc/ssl/dhparams_{{ site_name }}.pem {% if site.ssl.dhparam.numbits is defined %}{{ site.ssl.dhparam.numbits }}{% else %}2048{% endif %}
  - unless: "test -f /etc/ssl/dhparams_{{ site_name }}.pem && [ $(openssl dhparam -inform PEM -in /etc/ssl/dhparams_{{ site_name }}.pem -check -text | grep -Po 'DH Parameters: \\(\\K[0-9]+') = {% if site.ssl.dhparam.numbits is defined %}{{ site.ssl.dhparam.numbits }}{% else %}2048{% endif %} ]"
  - require:
    - pkg: nginx_packages
  - watch_in:
    - module: nginx_config_test
{% endif %}

{%- if site.ssl.get('ticket_key', {'enabled': False}).enabled %}
nginx_generate_{{ site_name }}_ticket_key:
  cmd.run:
  - name: openssl rand {% if site.ssl.ticket_key.numbytes is defined %}{{ site.ssl.ticket_key.numbytes }}{% else %}48{% endif %} > /etc/ssl/ticket_{{ site_name }}.key
  - unless: "test -f /etc/ssl/ticket_{{ site_name }}.key && [ $(wc -c < /etc/ssl/ticket_{{ site_name }}.key) = {% if site.ssl.ticket_key.numbytes is defined %}{{ site.ssl.ticket_key.numbytes }}{% else %}48{% endif %} ]"
  - require:
    - pkg: nginx_packages
  - watch_in:
    - module: nginx_config_test
{% endif %}

{%- if site.ssl.get('password_file', {'enabled': False}).enabled and site.ssl.password_file.file is not defined and site.ssl.password_file.content is defined %}
/etc/ssl/password_{{ site_name }}.key:
  file.managed:
  - contents_pillar: nginx:server:site:{{ site_name }}:ssl:password_file:content
  - require:
    - pkg: nginx_packages
  - watch_in:
    - module: nginx_config_test
{% endif %}
{% endif %}



{%- if site.get('ssl', {'enabled': False}).enabled and site.host.name not in ssl_certificates.keys() %}
{%- set _dummy = ssl_certificates.update({site.host.name: []}) %}

{%- set ca_file=site.ssl.get('ca_file', '') %}
{%- set key_file=site.ssl.get('key_file', '/etc/ssl/private/{0}.key'.format(site.host.name)) %}
{%- set cert_file=site.ssl.get('cert_file', '/etc/ssl/certs/{0}.crt'.format(site.host.name)) %}
{%- set chain_file=site.ssl.get('chain_file', '/etc/ssl/certs/{0}-with-chain.crt'.format(site.host.name)) %}

{%- if site.ssl.engine is not defined %}

{%- if site.ssl.key is defined %}

{{ site.host.name }}_public_cert:
  file.managed:
  - name: {{ cert_file }}
  {%- if site.ssl.cert is defined %}
  - contents_pillar: nginx:server:site:{{ site_name }}:ssl:cert
  {%- else %}
  - source: salt://pki/{{ site.ssl.authority }}/certs/{{ site.host.name }}.cert.pem
  {%- endif %}
  - require:
    - pkg: nginx_packages
  - watch_in:
    - module: nginx_config_test
    - cmd: nginx_init_{{ site.host.name }}_tls

{{ site.host.name }}_private_key:
  file.managed:
  - name: {{ key_file }}
  {%- if site.ssl.key is defined %}
  - contents_pillar: nginx:server:site:{{ site_name }}:ssl:key
  {%- else %}
  - source: salt://pki/{{ site.ssl.authority }}/certs/{{ site.host.name }}.key.pem
  {%- endif %}
  - mode: 400
  - require:
    - pkg: nginx_packages
    - file: /etc/ssl/private
  - watch_in:
    - cmd: nginx_init_{{ site.host.name }}_tls

{%- if site.ssl.chain is defined or site.ssl.authority is defined %}
{%- set ca_file=site.ssl.get('ca_file', '/etc/ssl/certs/{0}-ca-chain.crt'.format(site.host.name)) %}

{{ site.host.name }}_ca_chain:
  file.managed:
  - name: {{ ca_file }}
  {%- if site.ssl.chain is defined %}
  - contents_pillar: nginx:server:site:{{ site_name }}:ssl:chain
  {%- else %}
  - source: salt://pki/{{ site.ssl.authority }}/{{ site.ssl.authority }}-chain.cert.pem
  {%- endif %}
  - require:
    - pkg: nginx_packages
  - watch_in:
    - cmd: nginx_init_{{ site.host.name }}_tls

{% endif %}

{% endif %}

{% else %}
{# site.ssl engine is defined #}

{%- if site.ssl.authority is defined %}
{%- set ca_file=site.ssl.get('ca_file', '/etc/ssl/certs/ca-{0}.crt'.format(site.ssl.authority)) %}
{% endif %}

{% endif %}

{%- set old_chain_file = salt['cmd.shell']('cat {0}'.format(chain_file)) %}
{%- set new_chain_file = salt['cmd.shell']('cat {0} {1}'.format(cert_file, ca_file)) %}

{%- if site.ssl.get('engine', '') not in ['letsencrypt', 'k8s-sync'] %}
nginx_init_{{ site.host.name }}_tls:
  cmd.run:
  - name: "cat {{ cert_file }} {{ ca_file }} > {{ chain_file }}"
  - onlyif: {% if old_chain_file != new_chain_file %}/bin/true{% else %}/bin/false{% endif %}
  - watch_in:
    - module: nginx_config_test
{%- endif %}


{% endif %}

sites-available-{{ site_name }}:
  file.managed:
  - name: {{ server.vhost_dir }}/{{ site.get('name', site_name) }}.conf
  {%- if not site_type.startswith('nginx_') %}
  - source: salt://{{ site_type }}/files/nginx.conf }
  {%- else %}
  - source: salt://nginx/files/generic_server.conf
  {%- endif %}
  - template: jinja
  - require:
    - pkg: nginx_packages
  - watch_in:
    - module: nginx_config_test
  - defaults:
    site_name: "{{ site_name }}"



{%- if grains.os_family == 'Debian' %}
sites-enabled-{{ site_name }}:
  file.symlink:
  - name: /etc/nginx/sites-enabled/{{ site.get('name', site_name) }}.conf
  - target: {{ server.vhost_dir }}/{{ site.get('name', site_name) }}.conf
{%- endif %}
{%- else %}

{{ server.vhost_dir }}/{{ site.get('name', site_name) }}.conf:
  file.absent

{%- if grains.os_family == 'Debian' %}
/etc/nginx/sites-enabled/{{ site.get('name', site_name) }}.conf:
  file.absent
{%- endif %}

{%- endif %}
{%- endfor %}
