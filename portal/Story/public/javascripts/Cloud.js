function CloudAll(driver, name) {
  var self = this;
  self.driver = driver;
  self.name = self.nav = name;
  self.cache = {};
  
  self.resize = function () {
    var panel = $("#panel");
    panel.empty();
    for (var i = self.driver.start; i < self.driver.end; ++i) {
      self.addOffset(i, -1);
    }
    $('html, body').animate({ scrollTop: 0 }, 0);
  };

  self.right = function () {
    self.driver.start++;
    self.driver.end++;
    self.resize();
  };
  
  self.left = function (k) {
    if (self.driver.start == 0) {
      return;
    }
    self.driver.start--;
    self.driver.end--;
    self.resize();
  };
  
  self.addOffset = function(offset, pos) {
    var addOffsetHandler = function (data) {
      data = JSON.parse(data);
      
      // out of range request
      if (Object.keys(data).length == 0) return;

      var panel = $("#panel");
      var date_id = 'panel-' + data.date;
      var top = 0;
      var width = panel.width() / (self.driver.end - self.driver.start);
      
      // create date container
      var date_container =
        $('<div/>', {'id': date_id})
        //.css('position', 'absolute')
        .css('float', 'left')
        .css('top', top)
        //.css('left', left)
        .css('height', panel.height())
        .css('width', width);
      if (pos == -1) {
        date_container.appendTo(panel);
      }
      else {
        date_container.prependTo(panel);
      }
      
      // create date header
      $('<div/>', {'id':date_id+'-header', text:data.date})
      .css('width', width)
      .css('padding-bottom', '15px')
      .css('font-family', "'Fugaz One', cursive")
      .css('font-size', width/10)
      //.css('color', 'yellow')
      //.css('background-color', 'black')
      .css('vertical-align', 'middle')
      .css('text-align', 'center')
      .appendTo('#'+date_id);
      
      // sort topics by weight
      var sorted_topics = Object.keys(data.topics).sort(function(a,b) {
        return data.topics[b].weight - data.topics[a].weight;
      })
    
      // append topics
      $(sorted_topics).each(function (i,t) {
        //var topic_prior = data.topics[t].alpha / topic_total;
        //var topic_height = (panel.height()-header_height) * topic_prior;
        
        $('<div/>', {'text': data.topics[t].words.join(' ')})
        //.css('position', 'absolute')
        //.css('top', top)
        //.css('height', topic_height)
        .css('width', width - 5)
        .css('overflow', 'hidden')
        .css('font-size', Math.log(1+data.topics[t].weight)*(width/100)+width/10)
        .css('font-family', "'Josefin Sans', sans-serif")
        .css('word-spacing', '10%')
        .css('line-height', '120%')
        .css('border-style', 'solid')
        .css('border-width', 2)
        .css('margin', 1)
        .click(function () {
          self.driver.add_context(new CloudTopic(self.driver, self.name, t));
        })
        //.css('border-radius', 15)
        .appendTo('#'+date_id);
      });
      
      // decrement active counter
      self.active--;
    };
    if (offset in self.cache) {
      addOffsetHandler(self.cache[offset]);
    }
    else {
      $.ajax({url:'/cloud_data/' + self.name + '/' + offset,
              async: false})
      .done(function (data) {
        self.cache[offset] = data;
        addOffsetHandler(data);
      });
    }
  };
}

function CloudTopic(driver, name, topic) {
  var self = this;
  self.driver = driver;
  self.name = name;
  self.topic = self.nav = topic;
  self.data = [];
  self.range = [];
  
  self.resize = function () {
    var resize_helper = function () {
      self.active = 7;
      self.range = [];
      for (var i = self.driver.start; i < self.driver.end; ++i) {
        self.addOffset(i, -1);
      }
      $('html, body').animate({ scrollTop: self.top }, 0);
    }
    if (self.data.length == 0) {
      $.ajax({url:'/cloud_data_topic/' + self.name + '/' + self.topic,
              async: false})
      .done(function (data) {
        self.data = JSON.parse(data);
        self.center();
        resize_helper();
      });  
    }
    else {
      resize_helper();
    }
  };
  
  self.right = function () {
    if (self.driver.end == self.data.length) return;
    
    var first = self.range.shift();
    $('#'+first).remove();
    self.driver.start++;
    self.driver.end++;
    self.addOffset(self.driver.end - 1, -1);
  };
  
  self.left = function (k) {
    if (self.driver.start == 0) return;
    
    var last = self.range.pop();
    $('#'+last).remove();
    self.driver.start--;
    self.driver.end--;
    self.addOffset(self.driver.start, 0);
  };
  
  self.addOffset = function (offset, pos) {
    var panel = $("#panel");
    var data = self.data[offset];
    var date_id = 'panel-' + data.date;
    var top = 0;
    var width = panel.width() / (self.driver.end - self.driver.start) -1;
    
    // create date container
    var date_container =
      $('<div/>', {'id': date_id})
      .css('float', 'left')
      .css('top', top)
      .css('height', panel.height())
      .css('width', width);
    if (pos == -1) {
      date_container.appendTo(panel);
      self.range.push(date_id);
    }
    else {
      date_container.prependTo(panel);
      self.range.unshift(date_id);
    }
    
    // create date header
    $('<div/>', {'id':date_id+'-header', text:data.date})
    .css('width', width)
    .css('padding-bottom', '15px')
    .css('font-family', "'Fugaz One', cursive")
    .css('font-size', width/10)
    .css('vertical-align', 'middle')
    .css('text-align', 'center')
    .appendTo('#'+date_id);
  
    // append topics
    $(data.topics).each(function (i, t) {
      var td = $('<div/>')
              .css('width', width-5)
              .css('overflow', 'hidden')
              .css('font-size', Math.log(1+t.weight)*(width/100)+width/10)
              .css('font-family', "'Josefin Sans', sans-serif")
              .css('font-weight', t.id == self.topic ? 'bold' : 'normal')
              .css('word-spacing', '10%')
              .css('line-height', '120%')
              .css('border-style', 'solid')
              .css('border-width', 2)
              .append(
                $('<div/>', {'text': t.words.join(' ')})
                .css('border-bottom', 'solid')
                .css('margin', 10)
                .click(function () {
                    self.driver.add_context(new CloudTopic(self.driver, self.name, t.id));
                })
              )
              .appendTo('#'+date_id);
      
      $(t.documents.sort(function (a, b) { return b.weight - a.weight; }).slice(0,4)).each(function (j, d) {
        td.append(
          $('<div/>')
          .css('border-bottom', 'solid')
          .css('margin', 10)
          .append($('<a href="' + d.url + '" target="_blank">' + d.title + '</a>')));
      })
    });
  };
  
  self.center = function () {
    // set the pointers for start and end
    for (var i = 0; i < self.data.length; ++i) {
      if (self.data[i].topics.length > 0 && self.data[i].topics[0].id == self.topic) {
        self.driver.start = i;
        break;
      }
    }
    // try to center around topic in question
    if (self.driver.start + 4 > self.data.length) {
      self.driver.start -= self.driver.start + 4 - self.data.length;
      self.driver.end = self.driver.start + 4;
    }
    else if (self.driver.start - 3 < 0) {
      self.driver.start = 0;
      self.driver.end = 7;
    }
    else {
      self.driver.start = self.driver.start - 3;
      self.driver.end = self.driver.start + 7;
    }
  };
}
