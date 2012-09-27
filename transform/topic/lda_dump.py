from gensim import corpora, models, similarities, utils
import os
import re
import logging
import csv

logging.basicConfig(format='%(asctime)s : %(levelname)s : %(message)s', level=logging.INFO)
model = models.LdaModel.load('corpus-small.model')

ntopics = 50
nterms = 100
topics = model.show_topics(topics=ntopics, topn=nterms, log=False, formatted=False)

fh = open('topics.csv', 'w+')
fh_csv = csv.writer(fh)
fh_csv.writerow([('Term (%d)' if n % 2 == 0 else 'Score (%d)') % (n/2)  for n in range(2*ntopics)])
for t in range(100):
    fh_csv.writerow([(topics[n/2][t][1] if n % 2 == 0 else topics[n/2][t][0]) for n in range(2*ntopics)])

