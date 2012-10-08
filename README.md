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
  * A group name for the collection of rss feed data (used in the database).
* start
  * A date to begin downloading documents.
* end
  * A date to stop downloading documents.
* feeds
  * An array of RSS feeds containing a name and url.  The URL must point to a valid RSS feed.

Backend Processes
-----------------
The backend processes are primarilly comprised of lightweight perl wrappers that invoke pre-built java executables.  The perl scripts exist to make managing configuration and system tasks easier, while the java executable exist to make a subtask fast.  

The highlevel design of the backend infrastructure can be viewed as a series of filters that apply to a previously downloaded file.  The sequences of processes that need to run are listed below:

* Create the metadata files for each new story.  One yaml file per document will be created for the stories contained in the RSS feeds from the master configuration file.  These files will be stored by in seperate directories relative to the 'docroot' by date.
  * `perl ./rss/sync.pl conf/news.yaml`
* Download the text data for each story.  The URL in the yaml file will be downloaded and the text content will be extracted into a txt file at the same location as the original text file.
  * `perl ./rss/downloader.pl conf/news.yaml`
* Apply NLP extraction.  The text documents are processed using Apache's OpenNLP library to extract names, nouns, locations, and organizations.
  * `perl ./transform/nlp.pl conf/news.yaml`
* Apply Topic Modeling.  An entire directory of text files is processed with LDA topic modeling using the Mallet library.  
  * `perl ./transform/topic.pl conf/news.yaml` 
* Import data to database.  The data above is imported into a MySQL database for display purpose from the portal.
  * `perl ./import/import.pl conf/news.yaml`
* Apply edge creation.  Similarities between topic model data will precomputed over one month's time.  These topic similarites link stories together.  
  * `perl ./import/edge.pl conf/news.yaml`
* Display.  There is a portal to explore edge data and query over the dataset.
  * `perl portal/Story/bin/app.pl --port <port>` 

