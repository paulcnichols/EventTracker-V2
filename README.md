EventTracker-V2
===============

This project contains the infrastructure to create story graphs from RSS feeds.

Configuration
------------
The collection of RSS feeds, among other items, is configured with a YAML file.  A provided sample is available in the conf/ directory.

The following items are valid configurable settings:
* binroot
  * The root directory this project is synced to.
* docroot
  * The directory where documents are stored.
* name
  * A group name for the collection of rss feed data.
* start
  * A date to begin downloading documents.
* end
  * A date to stop downloading documents.
* feeds
  * An array of RSS feeds containing a name and url.  The URL must point to a valid RSS feed.

Backend Processes
-----------------
The backend processes are primarilly comprised of lightweight perl wrappers that invoke pre-built java executables.  The perl scripts exist primarilly to make managing configuration and system tasks easier, while the java executable exist to make a subtask fast.  

The highlevel design of the backend infrastructure is a series of filters that apply to a previously downloaded file.  The sequences of processes that need to run are listed below.

* Create the meta-data for each story.  One yaml file per document will be created from the RSS feeds in the master configuration file.
  * `perl ./rss/sync.pl conf/news.yaml`
* Download the text data for each story.  The URL in the yaml file will be downloaded and the text content will be extracted into a txt file.
  * `perl ./rss/downloader.pl conf/news.yaml`
* Apply NLP extraction.  The txt documents are processed using Apache's OpenNLP library to extract names, nouns, locations, and organizations.
  * `perl ./transform/nlp.pl conf/news.yaml`
* Apply Topic Modeling.  An entire directory of txt files is processed with LDA topic modeling using the Mallet library.  
  * `perl ./transform/topic.pl conf/news.yaml` 


