function Grapher(dataset, id) {
  this.dataset = dataset;
  this.id = id;
  this.plot = function (data) {

    // convert strings to numbers
    $.each(data.nodes, function (i, n) {
      n.id = parseInt(n.id);
      n.published = parseInt(n.published);
    });
    
    
    $.each(data.edges, function (i, e){
      e.a_id = parseInt(e.a_id);
      e.b_id = parseInt(e.b_id);
      e.weight = parseFloat(e.weight);
    });
    
    // sort the nodes for easier access/calculation of min/max
    data.nodes = data.nodes.sort(function (a, b) {
      return a.published - b.published;
    });
    
    var x_max = 700;
    var y_max = 420;
    var x_pad = 40;
    var y_pad = 30;
    
    // get the min and max for scaling purposes
    var tot = data.nodes.length;
    var min_t = data.nodes[0].published;
    var max_t = data.nodes[tot-1].published;
    if (min_t == max_t) return;
    
    // Creates canvas 
    var paper = Raphael(25, 25, x_max + 2*x_pad, y_max + 2*y_pad);
    
    // Draw x axis
    paper.path(['M', x_pad, y_pad + y_max, 'H', x_pad + x_max].join(' '))
         .attr({'stroke':'grey'});
    var d = 1;
    var start_d = new Date(new Date(1000*min_t).toDateString());
    while (start_d.getTime() + d*24*60*60*1000 < max_t*1000) {
      var nd = new Date(start_d.getTime() + d*24*60*60*1000);
      var dx = x_pad + x_max*(nd.getTime()/1000 - min_t)/(max_t-min_t);
      var dy = y_pad + y_max;
      paper.path(['M', dx, dy, 'v', 5]);
      if (nd.getDay() == 0) {
        paper.text(dx, dy+10, (nd.getMonth()+1) + '/' + nd.getDate() + '/' + nd.getFullYear())
      }
      d = d + 1;
    }
    
    // Draw y axis
    paper.path(['M', x_pad, y_pad, 'V', y_pad + y_max].join(' '))
         .attr({'stroke':'grey'});
    
    // Transform nodes into convenient, indexed form
    var nodes = [];
    var node_map = {};
    $.each(data.nodes, function (i, n) {
      n.height = 0;
      node_map[n.id] = nodes.length;
      nodes.push(n);
    });
    
    // Look at node edges for height
    $.each(data.edges, function (i, e) {
      nodes[node_map[e.a_id]].height += e.weight;
      node_map[e.b_id].height += e.weight;
    });
    
    // Calculate min/max height to scale
    var min_h = 1000000;
    var max_h = -1000000;
    $.each(nodes, function (i, n) {
      if (n.height > max_h)
        max_h = n.height;
      if (n.height < min_h)
        min_h = n.height;
    });
    
    // Plot the nodes
    $.each(nodes, function (i, n) {
      // plot a circle for the node
      n.px = x_pad + ((n.published-min_t)/(max_t-min_t))*x_max;
      //n.py = y_pad / 2 + (i/tot)*y_max;
      n.py = y_pad + ((n.height-min_h)/(max_h-min_h))*y_max;
      n.radius = 4;
      n.edges = [];
      n.peers = [];
      n.circle = paper.circle(n.px, n.py, n.radius).attr({fill:'grey', 'stroke-width':2});
      
      // set a tooltip
      n.circle.attr({title:n.title});
      
      // set flag to denote clicked status
      n.circle.clicked = 0;
      
      // color when hovering
      n.circle.hover(
        function () {
          if (n.circle.clicked) return;
          
          $.each(n.edges, function (j, e) {
            e.attr({stroke:'red'}).toFront();
          });
          $.each(n.peers, function (j, p) {
            p.circle.attr({fill:'yellow', stroke:'red'}).toFront();
          });
          n.circle.attr({fill:'yellow', stroke:'red'}).toFront();
        },
        function () {
          if (n.circle.clicked) return;
          
          $.each(n.edges, function (j, e) {
            e.attr({stroke:'black'}).toBack()
          });
          $.each(n.peers, function (j, p) {
            p.circle.attr({fill:'grey', stroke:'black'});
          });
          n.circle.attr({fill:'grey', stroke:'black'});
          $.each(nodes, function (j, p) { p.circle.toFront(); } );
        }
      );
      /*
      // make color sticky on click
      n.circle.click(
        function () {
          if (n.circle.clicked == 0) {
            $.each(n.edges, function (j, e) {
              e.attr({stroke:'blue'}).toFront();
              e.clicked = 1;
            });
            $.each(n.peers, function (j, p) {
              p.circle.attr({fill:'green', stroke:'blue'}).toFront();
              p.clicked = 1;
            });
            n.circle.clicked = 1;
            n.circle.attr({fill:'yellow', stroke:'blue'}).toFront();
          }
          else {
            $.each(n.edges, function (j, e) {
              e.attr({stroke:'black'}).toFront().toFront();
              e.clicked = 0;
            });
            $.each(n.peers, function (j, p) {
              p.circle.attr({fill:'grey', stroke:'black'});
              p.clicked = 0;
            });
            n.circle.clicked = 0;
            n.circle.attr({fill:'grey', stroke:'black'});
          }
        }
      );
      */
    });
    
    // Plot the edges
    $.each(data.edges, function (i, e) {
      var a = nodes[node_map[e.a_id]];
      var b = nodes[node_map[e.b_id]];
      if (b.published < a.published) {
        var tmp = a;
        a = b;
        b = tmp;
      }
      var s = ['M', a.px, a.py, 'C', a.px + .2*(b.px-a.px),
                                     a.py + .8*(b.py-a.py),
                                     b.px - .8*(b.px-a.px),
                                     b.py - .2*(b.py-a.py),
                                     b.px, b.py];
      
      var p = paper.path(s.join(' ')).attr({stroke:'black', 'stroke-width': 1+e.cosign_freq*6});
      p.clicked = 0;
      p.hover(
        function () {
          if (p.clicked == 1) return;
          p.attr({stroke:'red'}).toFront();
          a.circle.attr({stroke:'red', fill:'yellow'}).toFront();
          b.circle.attr({stroke:'red', fill:'yellow'}).toFront();
        },
        function () {
          if (p.clicked == 1) return;
          p.attr({stroke:'black'}).toBack();
          a.circle.attr({fill:'grey', stroke:'black'});
          b.circle.attr({fill:'grey', stroke:'black'});          
          $.each(nodes, function (j, p) { p.circle.toFront(); } );
        }
      );
      p.click(
        function () {
          
        }
      );
      a.edges.push(p);
      b.edges.push(p);
      a.peers.push(b);
      b.peers.push(a);
    });
    $.each(nodes, function (j, p) { p.circle.toFront(); } );
  };
  this.update = function () {
    $.get('/' + dataset + '/subgraph/' + id, this.plot);
  }
}