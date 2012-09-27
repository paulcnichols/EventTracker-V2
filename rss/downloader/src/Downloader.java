import org.apache.commons.io.*;
import net.htmlparser.jericho.*;
import java.io.*;
import java.util.*;
import java.net.*;
import java.util.concurrent.*;

public class Downloader {
	
	public static int nfetched = 0;
	public static int nfailed = 0;
	public static int nskipped = 0;

	public static void main(String[] args) throws Exception {
		
		// Handle command line arguments
		if (args.length < 2) {
			System.out.println("Usage:\n\t<num-threads> <url-file>");
			System.exit(1);
		}
		
		// Create the thread pool
		int nthreads = Integer.parseInt(args[0]);
		ExecutorService service = Executors.newFixedThreadPool(nthreads);

		// Disable Jericho's overly verbose logging
		Config.LoggerProvider=LoggerProvider.DISABLED;
		
		// Load the file 
		String file = args[1];
		try {
			String line;
			BufferedReader in = new BufferedReader(new FileReader(new File(file)));
			while((line = in.readLine()) !=  null) {
				service.submit(new Handler(line));
			}
		} catch(FileNotFoundException e) {
			System.out.println("Error: Failed to load file '" + file + "'!");
		} finally {
		}
		
		// Wait for the thread pool to finish
		service.shutdown();
	}

	// Thread
	static class Handler implements Runnable {
		private String line;
		Handler(String line) { this.line = line; }
		 
		public void run() {
			if ((nfetched + nfailed + nskipped + 1) % 100 == 0) {
				System.out.println("Status: " + nfetched + " fetched, " + nfailed + " failed, " + nskipped + " skipped.");
			}
			
			String kv[] = line.split("\t");
			File success = new File(kv[0]+".txt");
			File bow = new File(kv[0]+".bow");
			File failure = new File(kv[0]+".failed"); 
			try {
				
				// Skip previously processed files
				if (success.exists() || failure.exists()) {
					nskipped += 1;
					return;
				}
				
				// Use jericho's built in downloader to extract text
				URL u = new URL(kv[1]);
				Source source = new Source(u);
				String txt = source.getRenderer().toString();
				txt = txt.replaceAll("<[^>]*>", "");
				
				// Write the resulting text content to a txt file
				FileUtils.writeStringToFile(success, txt);
				
				// Process file into bag-of-words format while here
				String words [] = txt.split("\\W+");
				Map<String, Integer> word_count = new HashMap<String, Integer>();
				for (String word : words) {
					if (word.length() == 0) 
						continue;
					int count = word_count.containsKey(word) ? word_count.get(word) : 0;
					word_count.put(word, count + 1);
				}
				String bow_data = "";
				for (Map.Entry<String, Integer> w : word_count.entrySet()) {
					bow_data += w.getKey() + "\t" + w.getValue() + "\n";
				}
				FileUtils.writeStringToFile(bow, bow_data);
				
				nfetched += 1;
				
			} catch (Exception e) {
				// Write a failure file to avoid re-downloading
				try {
					FileUtils.writeStringToFile(failure, e.toString());
				} catch (Exception e2) {
				}
				nfailed += 1;
				System.out.println("Error: Failed to get " + kv[1]);
			}
		}
	}
}
