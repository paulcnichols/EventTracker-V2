import opennlp.tools.postag.POSModel;
import opennlp.tools.postag.POSTaggerME;

import opennlp.tools.sentdetect.SentenceModel;
import opennlp.tools.sentdetect.SentenceDetectorME;

import opennlp.tools.namefind.TokenNameFinderModel;
import opennlp.tools.namefind.NameFinderME;

import opennlp.tools.tokenize.TokenizerModel;
import opennlp.tools.tokenize.TokenizerME;

import opennlp.tools.util.Span;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.io.IOException;
import java.io.FileInputStream;
import java.util.Arrays;
import java.util.List;
import java.util.ArrayList;

import org.apache.commons.io.FileUtils;
import org.apache.commons.lang3.StringUtils;

public class nlp {
	public static void main(String[] args) throws IOException {

		// Get the files
		if (args.length < 2) {
			System.out.println("usage: ./nlp <model-dir> <file-list>");
			System.exit(1);
		}
		String model_dir = args[0];
		String file_list = args[1];

		// Load the POS tagger
		POSTaggerME pos = new POSTaggerME(
				new POSModel(
						new FileInputStream(model_dir + "/en-pos-maxent.bin")));

		// Load the Sentence Detector
		SentenceDetectorME sent = new SentenceDetectorME(
				new SentenceModel(
						new FileInputStream(model_dir + "/en-sent.bin")));

		// Load the tokenizer
		TokenizerME tokenizer = new TokenizerME(
				new TokenizerModel(
						new FileInputStream(model_dir + "/en-token.bin")));
		// Location finder
		NameFinderME l_finder = new NameFinderME(
				new TokenNameFinderModel(
						new FileInputStream(model_dir + "/en-ner-location.bin")));

		// Organization finder
		NameFinderME o_finder = new NameFinderME(
				new TokenNameFinderModel(
						new FileInputStream(model_dir + "/en-ner-organization.bin")));

		// Person finder
		NameFinderME p_finder = new NameFinderME(
				new TokenNameFinderModel(
						new FileInputStream(model_dir + "/en-ner-person.bin")));

		// Extract nouns, verbs, and adjectives
		BufferedReader br = new BufferedReader(new FileReader(file_list));
		String file;
		while((file = br.readLine()) != null) {
			String content = FileUtils.readFileToString(new File(file));
			String [] sentences = sent.sentDetect(content);

			List<String> n_list= new ArrayList<String>();
			List<String> l_list= new ArrayList<String>();
			List<String> o_list= new ArrayList<String>();
			List<String> p_list = new ArrayList<String>();

			System.out.println("Status: " + file);

			for (String sentence : sentences) {
				String tokens[] = tokenizer.tokenize(sentence);

				String[] tags = pos.tag(tokens);
				for (int i=0; i < tags.length; ++i) {
					String t = tags[i];
					String k = tokens[i];

					// Noun, singular or mass noun
					// Noun, plural
					if (t.equals("NN") || t.equals("NNS") || t.equals("NNP") || t.equals("NNPS")) {
						n_list.add(k);
					}
				}

				Span[] locs = l_finder.find(tokens);
				for (Span s : locs) {
					l_list.add(StringUtils.join(Arrays.copyOfRange(tokens, s.getStart(), s.getEnd()), " "));
				}

				Span[] orgs = o_finder.find(tokens);
				for (Span s : orgs) {
					o_list.add(StringUtils.join(Arrays.copyOfRange(tokens, s.getStart(), s.getEnd()), " "));
				}

				Span[] peeps = p_finder.find(tokens);
				for (Span s : peeps) {
					p_list.add(StringUtils.join(Arrays.copyOfRange(tokens, s.getStart(), s.getEnd()), " "));
				}
			}

			if (n_list.size() > 0)
				FileUtils.writeLines(new File(file+".nouns"), n_list);

			if (l_list.size() > 0)
				FileUtils.writeLines(new File(file+".locs"), l_list);

			if (o_list.size() > 0)
				FileUtils.writeLines(new File(file+".orgs"), o_list);

			if (p_list.size() > 0)
				FileUtils.writeLines(new File(file+".names"), p_list);

		}
	}
}

