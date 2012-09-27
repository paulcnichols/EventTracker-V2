from gensim import corpora, models, similarities, utils
import logging
import os
import re

logging.basicConfig(format='%(asctime)s : %(levelname)s : %(message)s', level=logging.INFO)

class DirectoryCorpus(corpora.TextCorpus):

    def get_texts(self):
        length = 0
        for root, dirs, files in os.walk(self.input):
            for f in files:
                try:
                    content = ''
                    with open(root + '/' + f, 'r') as content_file:
                        content = utils.any2utf8(content_file.read())
                    length += 1
                    yield re.split(r'\W+', content.lower())
                except:
                    pass
        self.length = length

corp_name = 'corpus-small'
corp = DirectoryCorpus(corp_name)

npasses = 50
ntopics = 50
nterms = 100
model = models.LdaModel(corpus=corp, id2word=corp.dictionary, passes=npasses, num_topics=ntopics, distributed=False)
model.save(corp_name + '.model')

fh = open('topics.csv', 'w+')
fh_csv = csv.writer(fh)
fh_csv.writerow([('Term (%d)' if n % 2 == 0 else 'Score (%d)') % (n/2)  for n in range(2*ntopics)])
for t in range(100):
    fh_csv.writerow([(topics[n/2][t][1] if n % 2 == 0 else topics[n/2][t][0]) for n in range(2*ntopics)])


