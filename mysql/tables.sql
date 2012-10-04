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
  PRIMARY KEY (`id`),
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
  KEY `date` (`date`)
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
  `document_id` int not null,
  `topic_id` int not null,
  `weight` float,
  KEY (`document_id`, `topic_id`),
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
