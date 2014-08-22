class drupal {
  package { php: ensure => latest }

  package { mysql:
    ensure => latest,
    require => Package["php"]
  }

  package { php-mysql:
    ensure => latest,
    require => Package["mysql"]
  }

  package { php-gd:
    ensure => latest,
    require => Package["php-mysql"]
  }

  package { php-drush-drush:
    ensure => latest,
    require => Package["php-gd"]
  }

  exec { 'drupal-download':
    command => "/usr/bin/drush dl drupal --drupal-project-rename=drupal -y",
    cwd => "/var/www",
    unless => "/usr/bin/test -f /var/www/drupal/index.php",
    require => Package["php-drush-drush"]
  }

  exec { 'drupal-install':
    command => "/usr/bin/drush si standard \
      --db-url=mysql://${cfn_user}:${cfn_password}@${cfn_host}/${cfn_database} \
      --db-su=${cfn_user} \
      --db-su-pw=${cfn_password} \
      --account-pass=admin \
      --site-name='Drupal Enterprise' \
      -y",
    cwd => "/var/www/drupal",
    unless => "/usr/bin/test -f /var/www/drupal/sites/default/settings.php",
    require => Exec["drupal-download"]
  }

  file { "/etc/httpd/conf.d/drupal.conf":
    content => template('drupal/drupal.conf.erb'),
    require => Package["php-drush-drush"]
  }

  service { httpd:
    enable => true,
    ensure => "running",
    require => File["/etc/httpd/conf.d/drupal.conf"]
  }
}
