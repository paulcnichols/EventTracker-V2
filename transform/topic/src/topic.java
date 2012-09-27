import cc.mallet.types.*;
import cc.mallet.pipe.*;
import cc.mallet.topics.*;

import java.util.*;
import java.io.*;

import org.apache.commons.io.FileUtils;

public class topic {
	public static final int TOP_TERMS_PER_TOPIC = 100;
	
	public static void main(String[] args) throws Exception {

		if (args.length < 2) {
			System.out.println("usage:\n\ttopic <directory> <ntopics> <stop-words-file>");
			System.exit(1);
		}
		String directory = args[0];
		int numTopics = Integer.parseInt(args[1]);
		String stopwords = "";
		if (args.length > 2)
			stopwords = args[2];
		
		// Begin by importing documents from text to feature sequences
		ArrayList<Pipe> pipeList = new ArrayList<Pipe>();
	
		// Pipes: lowercase, tokenize, remove stopwords, map to features
		pipeList.add(new CharSequenceLowercase());
		pipeList.add(new CharSequence2TokenSequence("\\w+"));
		if (stopwords.length() > 0) 
			pipeList.add(new TokenSequenceRemoveStopwords(new File(stopwords), "UTF-8", false, false, false));
		pipeList.add(new TokenSequence2FeatureSequence());
		
		// Load instances in directory ending with .txt
		InstanceList instances = new InstanceList (new SerialPipes(pipeList));
		for (File f : new File(directory).listFiles()) {
			if (f.toString().endsWith(".txt")) {
				String content = FileUtils.readFileToString(f, "UTF-8");
				content = content.replaceAll("\\p{Punct}", "");
				instances.addThruPipe(
					new Instance(content, null, f.toString(), null));
			}
		}
		
		// Start model with alpha_t = 0.01, beta_w = 0.01
		ParallelTopicModel model = new ParallelTopicModel(numTopics, 1.0, 0.01);
		model.addInstances(instances);
		model.setOptimizeInterval(10);
		model.setNumThreads(2);
		model.setNumIterations(2000);
		model.estimate();

		// Save the document-topic distributions
		for (int i = 0; i < instances.size(); ++i) {
			ArrayList<String> lines = new ArrayList<String>();
			double[] topicDistribution = model.getTopicProbabilities(i);
			for (int topic = 0; topic < numTopics; ++topic) {
				lines.add(
					String.format(
						"%d, %f", 
						topic, 
						topicDistribution[topic]));
			}
			String source = (String) instances.get(i).getName();
			FileUtils.writeLines(new File(source + ".topics"), lines);
		}

		// Save the topic distribution (Alpha)
		ArrayList<String> alpha = new ArrayList<String>();
		for (int topic = 0; topic < numTopics; topic++) {
			alpha.add(String.format("%d, %f", topic, model.alpha[topic]));
		}
		if (directory.endsWith("/"))
			directory = directory.substring(0,directory.length());
		FileUtils.writeLines(new File(directory + ".alpha"), alpha);
		
		// Save the topic-term distributions (Beta)
		Alphabet dataAlphabet = instances.getDataAlphabet();
		ArrayList<TreeSet<IDSorter>> topicSortedWords = model.getSortedWords();
		ArrayList<String> beta = new ArrayList<String>();
		for (int topic = 0; topic < numTopics; ++topic) {
			Iterator<IDSorter> iterator = topicSortedWords.get(topic).iterator();
			while (iterator.hasNext()) {
				IDSorter idCountPair = iterator.next();
				beta.add(
					String.format(
						"%d, %s, %f", 
						topic, 
						dataAlphabet.lookupObject(idCountPair.getID()), 
						idCountPair.getWeight()));
			}
		}
		FileUtils.writeLines(new File(directory + ".beta"), beta);
	}
}
