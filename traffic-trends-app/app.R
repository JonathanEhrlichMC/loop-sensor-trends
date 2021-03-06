source("global.R")
#### UI #### -----
ui <- fluidPage(
    titlePanel("Metro Area Vehicle Miles Traveled on MnDOT Roads"),
    sidebarLayout(
        sidebarPanel(width = 2,
                     h3("Select date"),
                     # Date selector
                     dateInput("selected_date", "Date:",
                               value = "2020-03-23",
                               min = min(diffs_dt$date), max = max(diffs_dt$date),
                               format = "yyyy-mm-dd", startview = "month"
                     )
                     
                     
        ),
        
        # Application title
        mainPanel(
            # Map and Plot
            fluidRow(
                column(10,
                       leafletOutput("mymap", height = "600px")
                )
            ),
            fluidRow( width = 10, 
                      
                plotOutput("graph")
                
            )
        )
    )
        
    )
    
    #### Server #### -----
    server <- function(input, output) {
        output$graph <- renderPlot({
            ggplot(
                diffs_4plot[doy > 61 & year == 2020],
                aes(
                    x = date, y = `Difference from Typical VMT (%)`,
                    group = year,
                    text = paste0(
                        "Date: ", date, " (", weekday, ")",
                        "<br>Typical VMT: ", round(vmt.predict / 1000000, 1),
                        " M (", round(vmt.predict / hh_total), " miles per household)",
                        "<br>Actual VMT: ", round(vmt.sum / 1000000, 1),
                        " M (", round(vmt.sum / hh_total), " miles per household)",
                        "<br>Difference from Typical VMT: ", round(`Difference from Typical VMT (%)`), " %"
                    ),
                )
            ) +
                theme_minimal() +
                geom_point() +
                geom_line() +
                scale_x_date(date_breaks = "day", date_labels = "%b %d\n(%A)") +
                geom_hline(yintercept = 0) +
                ggtitle("Metro Area Traffic on MnDOT Roads") +
                theme(legend.position = "none") +
                labs(x = "Date", y = "% Difference from Typical VMT\n(Vehicle Miles Traveled)")
        })
        
        # base map -------------------------------------------------------------------------------------------
        output$mymap <- renderLeaflet({
            leaflet(ctu_diffs_sf) %>%
                addProviderTiles("CartoDB.Positron") %>%
                addMapPane("polygons", zIndex = 410) %>%
                addMapPane("points", zIndex = 420) %>%
                addCircleMarkers(
                    data = node_sf, color = "white", radius = 2, fill = FALSE,
                    group = "Traffic Detector Locations",
                    options = leafletOptions(pane = "points")
                )
            # addPolygons(data = ctu_diffs_sf[ctu_diffs_sf$date == '2020-03-23' ,],
            #             color = ~binpal(avg.diff), stroke = T, fillOpacity = 0.75,
            #             label = ctu_labels[ctu_diffs_dt$date == '2020-03-23'])
        })
        
        binpal_ctu <- colorBin(palette = "PuOr", 
                               domain = ctu_diffs_dt$avg.diff,
                               bins = 5,
                               reverse = T)
        
        # when I select a date------------------------------------------------------
        observeEvent(input$selected_date, {
            new_ctu_diffs <- ctu_diffs_sf[as.character(ctu_diffs_sf$date) == input$selected_date, ]
            new_ctu_labels <- ctu_labels[as.character(ctu_diffs_dt$date) == input$selected_date]
            # new map - this date
            leafletProxy("mymap") %>%
                clearGroup("ctu_dat") %>%
                clearControls() %>% 
                addPolygons(
                    data = new_ctu_diffs,
                    fillColor = ~binpal_ctu(avg.diff),
                    color = "lightgray",
                    stroke = T, 
                    weight = 1,
                    fillOpacity = 0.85,
                    label = new_ctu_labels,
                    group = "ctu_dat",
                    options = leafletOptions(pane = "polygons"),
                    labelOptions = labelOptions(textsize = "1.6rem")
                ) %>% 
                addLegend(data = new_ctu_diffs,
                          position = "bottomright",
                          group = "legend",
                          pal = binpal_ctu,
                          title = "Avg. diff",
                          values = ~avg.diff,
                          labFormat = labelFormat(suffix = "%"))
        }) # end household marker click routine
    }
    
    # Run the application
    shinyApp(ui = ui, server = server)
    