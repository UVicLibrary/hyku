$(document).on('turbolinks:load', function() {
  $('.js-per-page__submit').hide();
  $('.js-per-page__select').on('change', function() {
    $(this).parents('.js-per-page').submit();
  });
  
  // Changes the header ("Featured ____") to match the tab that is currently active
  $("span#featured-header").html($("ul#featured-nav li.active").text());
  $("ul#featured-nav li a").click(function(){
    var featuredText = $(this).text();
    $("span#featured-header").html(featuredText);
  });

  // Refresh the collections or works list if user clicks pagination link
  $("#homepage-works-and-collections").on('click', '.pagination a', function() {
    var c = "#collections-partial";
    var w = "#works-partial";
    if ($(this).closest(c) || $(this).closest(w)) {
      $(this).closest(':has(tbody)').find('tbody').css('opacity','0.6');
      $(this).closest('.pagination').html('Loading results...');
      $.get(this.href, null, null, "script"); // views/hyrax/homepage/index.js.erb
      return false;
    }
    return false;
  });

  // Prevent Feature/Unfeature collection button from firing twice
  $('#feature-coll-link, #unfeature-coll-link').on('click', function() {
    $(this).prop('disabled', true);
  });

});
