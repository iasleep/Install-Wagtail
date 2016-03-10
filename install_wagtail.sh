#!/usr/bin/env bash
mkdir /usr/local/django/
yum -y update
yum -y install epel-release
yum install -y git python-pip nginx postgresql redis zlib-devel python-devel.x86_64 postgresql-server.x86_64 
yum install -y postgresql-devel.x86_64 postgresql-devel.i686 libjpeg-turbo-devel.x86_64 libjpeg-turbo.x86_64 mc nano 
yum install -y java-1.7.0-openjdk-headless.x86_64 libpqxx-devel.x86_64
yum -y groupinstall 'Development Tools'
/usr/bin/postgresql-setup initdb
perl -pi -e "s/^(local\s+all\s+all\s+)peer$/\1trust/" /var/lib/pgsql/data/pg_hba.conf
service postgresql restart
curl -O https://download.elastic.co/elasticsearch/elasticsearch/elasticsearch-1.0.0.noarch.rpm
rpm -Uhv elasticsearch-1.0.0.noarch.rpm
perl -pi -e"s/ network.host: 192.168.0.1/network.host: 127.0.0.1/" /etc/elasticsearch/elasticsearch.yml
systemctl enable elasticsearch.service
systemctl start elasticsearch.service
cd /usr/local/django/
 git clone https://github.com/torchbox/wagtaildemo.git mywagtail
cd mywagtail
dd if=/dev/zero of=/tmpswap bs=1024 count=524288
mkswap /tmpswap
swapon /tmpswap
pip install --upgrade pip
pip install virtualenv
virtualenv /usr/local/django/mywagtail/venv
source /usr/local/django/mywagtail/venv/bin/activate
pip install -r requirements.txt
swapoff -v /tmpswap
rm -rf /tmpswap
createdb -Upostgres wagtaildemo
sudo -u postgres createuser root
./manage.py migrate
./manage.py load_initial_data
./manage.py createsuperuser --username root --email admin@mail.com --noinput
yes yes | ./manage.py collectstatic
#./manage.py migrate
deactivate
pip install uwsgi
curl -O https://raw.githubusercontent.com/nginx/nginx/master/conf/uwsgi_params
cat << EOF > /etc/nginx/conf.d/default.conf
upstream django {
    server unix:///usr/local/django/mywagtail/uwsgi.sock;
}
server {
    listen      8000;
    charset     utf-8;
    client_max_body_size 75M; # max upload size
    location /media  {
        alias /usr/local/django/mywagtail/media;
    }
    location /static {
        alias /usr/local/django/mywagtail/static;
    }
    location / {
        uwsgi_pass  django;
        include     /usr/local/django/mywagtail/uwsgi_params;
    }
}
EOF
cat << EOF > /usr/local/django/mywagtail/uwsgi_conf.ini
[uwsgi]
home            = /usr/local/django/mywagtail/venv/
chdir           = /usr/local/django/mywagtail/
module          = wagtaildemo.wsgi
master          = true
processes       = 10
socket          = /usr/local/django/mywagtail/uwsgi.sock
chmod-socket    = 666
vacuum          = true
module          = wagtaildemo.wsgi:application
EOF
sed -i 's/enforcing/disabled/g' /etc/sysconfig/selinux /etc/sysconfig/selinux

cat <<EOF> /etc/systemd/system/uwsgi.service
[Unit]
Description=uWSGI instance to serve myproject
After=network.target

[Service]
WorkingDirectory=/usr/local/django/mywagtail/
Environment="PATH=/usr/local/django/mywagtail/venv/bin"
ExecStart=/bin/uwsgi --ini /usr/local/django/mywagtail/uwsgi_conf.ini

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF> /usr/local/django/mywagtail/wagtaildemo/urls.py
from django.conf.urls import include, url
from django.conf.urls.static import static
from django.conf import settings
from django.contrib import admin

from wagtail.wagtailadmin import urls as wagtailadmin_urls
from wagtail.wagtaildocs import urls as wagtaildocs_urls
from wagtail.wagtailcore import urls as wagtail_urls
from wagtail.contrib.wagtailapi import urls as wagtailapi_urls

from demo import views


urlpatterns = [
    url(r'^django-admin/', include(admin.site.urls)),

    url(r'^admin/', include(wagtailadmin_urls)),
    url(r'^documents/', include(wagtaildocs_urls)),

    url(r'search/$', views.search, name='search'),
    url(r'^api/', include(wagtailapi_urls)),

    # For anything not caught by a more specific rule above, hand over to
    # Wagtail's serving mechanism
    url(r'', include(wagtail_urls)),
]


if settings.DEBUG:
    from django.contrib.staticfiles.urls import staticfiles_urlpatterns
    from django.views.generic.base import RedirectView

    urlpatterns += staticfiles_urlpatterns()
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
    urlpatterns += [
        url(r'^favicon\.ico$', RedirectView.as_view(url=settings.STATIC_URL + 'demo/images/favicon.ico', permanent=True))
		]
EOF
service nginx restart
service uwsgi start
service redis start
service postgresql start
systemctl enable uwsgi.service
systemctl enable nginx.service
systemctl enable redis
systemctl enable postgresql
reboot



