import cc.mallet.types.*;
import cc.mallet.pipe.*;
import cc.mallet.topics.*;
import cc.mallet.util.Randoms;

import java.util.*;
import java.io.*;

import org.apache.commons.io.FileUtils;

public class htopic {
	
	public static void main(String[] args) throws Exception {

		if (args.length < 1) {
			System.out.println("usage:\n\thtopic <directory>");
			System.exit(1);
		}
		String directory = args[0];
		
		// Begin by importing documents from text to feature sequences
		ArrayList<Pipe> pipeList = new ArrayList<Pipe>();
	
		// Pipes: lowercase, tokenize, remove stopwords, map to features
		pipeList.add(new CharSequenceLowercase());
		pipeList.add(new CharSequence2TokenSequence("\\w+"));
		pipeList.add(new TokenSequenceRemoveStopwords(new File("stoplists/en.txt"), "UTF-8", false, false, false));
		pipeList.add(new TokenSequence2FeatureSequence());
		
		// Load instances in directory ending with .txt
		InstanceList instances = new InstanceList (new SerialPipes(pipeList));
		for (File f : new File(directory).listFiles()) {
			if (f.toString().endsWith(".txt")) {
				String content = FileUtils.readFileToString(f, "UTF-8");
				instances.addThruPipe(
					new Instance(content, null, f.toString(), null));
			}
		}
		
		// Start model
		HierarchicalLDA model = new HierarchicalLDA();
		model.initialize(instances, null, 5, new Randoms());
		model.estimate(2000);
		
		// Save the sampler state
		if (directory.endsWith("/"))
			directory = directory.substring(0,directory.length());
		model.printState(new PrintWriter(new File(directory + ".htopic")));
	}
}
