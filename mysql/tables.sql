# database_root in configuration file
CREATE DATABASE `events`;
USE `events`;

CREATE TABLE `dataset` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` text,
  PRIMARY KEY (`id`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

CREATE TABLE `rss` (
  `dataset_id` int(11) NOT NULL,
  `url` text,
  KEY `DATASET` (`dataset_id`),
  FOREIGN KEY (dataset_id) REFERENCES dataset(id)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

CREATE TABLE `document` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `title` text,
  `url` text,
  `dataset_id` int,
  `published` int(11) NOT NULL,
  `date` date not null,
  PRIMARY KEY (`id`),
  KEY `date` (`date`),
  FOREIGN KEY (`dataset_id`) REFERENCES dataset(`id`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

CREATE TABLE `term` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `str` varchar(100) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `TERM` (`str`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

CREATE TABLE `entity` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `str` varchar(250) NOT NULL,
  `type` ENUM('NOUN', 'NAME', 'ORGANIZATION', 'LOCATION'),
  PRIMARY KEY (`id`),
  UNIQUE KEY `TERM` (`str`, `type`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

CREATE TABLE `document_term` (
  `document_id` int not null,
  `term_id` int not null,
  `count` int not null,
  PRIMARY KEY (`document_id`, `term_id`),
  FOREIGN KEY (`document_id`) REFERENCES document(`id`),
  FOREIGN KEY (`term_id`) REFERENCES term(`id`)  
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

CREATE TABLE `document_entity` (
  `document_id` int not null,
  `entity_id` int not null,
  `count` int not null,
  PRIMARY KEY (`document_id`, `entity_id`),
  FOREIGN KEY (`document_id`) REFERENCES document(`id`),
  FOREIGN KEY (`entity_id`) REFERENCES entity(`id`)  
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

CREATE TABLE `topic` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `dataset_id` int not null,
  `date` date,
  `alpha` float,
  PRIMARY KEY (`id`),
  KEY (`dataset_id`, `date`),
  KEY `date` (`date`),
  FOREIGN KEY (`dataset_id`) REFERENCES dataset(`id`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

CREATE TABLE `topic_term` (
  `topic_id` int not null,
  `term_id` int not null,
  `beta` float,
  FOREIGN KEY (`topic_id`) REFERENCES topic(`id`),
  FOREIGN KEY (`term_id`) REFERENCES term(`id`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

CREATE TABLE `document_topic` (
  `dataset_id` int not null,
  `document_id` int not null,
  `topic_id` int not null,
  `weight` float,
  KEY (`dataset_id`, `document_id`, `topic_id`),
  KEY (`document_id`, `topic_id`),
  KEY (`topic_id`),
  FOREIGN KEY (`dataset_id`) REFERENCES dataset(`id`),
  FOREIGN KEY (`document_id`) REFERENCES document(`id`),
  FOREIGN KEY (`topic_id`) REFERENCES topic(`id`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

CREATE TABLE `topic_similarity` (
  `topic_a` int,
  `topic_b` int,
  `cosign_similarity` float,
  PRIMARY KEY (`topic_a`, `topic_b`),
  FOREIGN KEY (`topic_a`) REFERENCES topic(`id`),
  FOREIGN KEY (`topic_b`) REFERENCES topic(`id`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

delimiter $$

CREATE TABLE `edge_intersection` (
  `document_a` int(11) NOT NULL DEFAULT '0',
  `document_b` int(11) NOT NULL DEFAULT '0',
  `topic_a` int(11) NOT NULL DEFAULT '0',
  `topic_b` int(11) NOT NULL DEFAULT '0',
  `topic_prod` float NOT NULL,
  `term_prob` float NOT NULL,
  `term_raw` float NOT NULL,
  `term_weighted` float NOT NULL,
  PRIMARY KEY (`document_a`,`document_b`,`topic_a`,`topic_b`),
  KEY `document_b` (`document_b`),
  KEY `topic_a` (`topic_a`),
  KEY `topic_b` (`topic_b`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1$$

