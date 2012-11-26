import java.io.*;
import java.util.*;

public class distance {
	public distance(float threshold) {
		m_threshold = threshold;
		m_dataset = new HashMap<Integer, HashMap<Integer, HashMap<Integer, Float>>>();
	}
	
	// Load feature in to internal maps
	public void LoadFeature(String s) {
    	// format of string will be:
    	// <offset>\t<id>\t(<feature_id>:<feature_count> )*\n
    	String sp[] = s.split(",");
    	if (sp.length != 3)
    		return;
    	
    	// parse the dataset id and the feature id
    	int dataset_id = Integer.parseInt(sp[0]);
    	int f_id = Integer.parseInt(sp[1]);
    	if (!m_dataset.containsKey(dataset_id)) {
    		m_dataset.put(dataset_id, new HashMap<Integer, HashMap<Integer,Float>>());
    	}
    	
    	// split out the feature vector
    	HashMap<Integer, Float> f = new HashMap<Integer, Float>(1000);
    	String fv[] = sp[2].split(" ");
    	for (int i = 0; i < fv.length; ++i) {
    		String kv[] = fv[i].split(":");
    		if (kv.length != 2)
    			continue;
    		f.put(Integer.parseInt(kv[0]), Float.parseFloat(kv[1]));
    	}
    	
    	// add new feature to dataset
    	m_dataset.get(dataset_id).put(f_id, f);
	}
	
	// Perform the cosign similarity distance measure
	public float Compare(HashMap<Integer, Float> a, HashMap<Integer, Float> b) {
		float p = 0;
		float anorm = 0;
		float bnorm = 0;
		for (Integer a_id : a.keySet()) {
			if (b.containsKey(a_id)) {
				p += a.get(a_id).floatValue()*b.get(a_id).floatValue();
			}
			anorm += a.get(a_id).floatValue()*a.get(a_id).floatValue();
		}
		anorm = (float) Math.sqrt(anorm);
		for (Float b_val : b.values()) {
			bnorm += b_val.floatValue()*b_val.floatValue();
		}
		bnorm = (float) Math.sqrt(bnorm);
		return p / (anorm * bnorm);
	}
	
	public void CompareAll() {
		HashMap<Integer, HashMap<Integer, Float>> centroid = m_dataset.get(0);
		for (Integer dataset_id : m_dataset.keySet()) {
			if (dataset_id.intValue() == 0)
				continue;
			
			HashMap<Integer, HashMap<Integer, Float>> b = m_dataset.get(dataset_id);
			for (Integer a_id : centroid.keySet()) {
				for (Integer b_id : b.keySet()) {
					float dist = Compare(centroid.get(a_id), b.get(b_id));
					if (dist > m_threshold) {
						System.out.printf(
								"%d,%d,%f\n", 
								a_id.intValue(), 
								b_id.intValue(),
								dist);
					}
				}
			}
		}
	}
	
	public static void main(String[] args) throws Exception {
		
		float threshold = (float) .3;
		if (args.length > 0)
			threshold = Float.parseFloat(args[0]);
		
		// container to hold data points
		distance d = new distance(threshold);
		
		// read items to compare from standard input
		BufferedReader in = new BufferedReader(new InputStreamReader(System.in));
	    String s;
	    while ((s = in.readLine()) != null && s.length() != 0) {
	    	d.LoadFeature(s);
	    }
	    
	    // do pairwise comparison with all other points and print to stdout
	    d.CompareAll();
	}
	
	private float m_threshold;
	private HashMap<Integer, HashMap<Integer, HashMap<Integer, Float>>> m_dataset;
}