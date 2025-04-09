// Clear any previous results
run("Clear Results");
run("Close All");
if (isOpen("ROI Manager")) {
    selectWindow("ROI Manager");
    run("Close");
}

// Create a dialog to set initial parameters
Dialog.create("Batch Processing Options");
Dialog.addDirectory("Input directory", "");
Dialog.addDirectory("Output directory", "");
Dialog.addNumber("Default minimum size (pixels)", 30);
Dialog.addNumber("Default maximum size (pixels)", 3000);
Dialog.addNumber("Default threshold ratio", 0.7);
Dialog.addNumber("Default blur radius", 50);
Dialog.addChoice("Outline color", newArray("yellow", "red", "green", "blue", "magenta", "cyan"));
Dialog.addCheckbox("Generate tif stack summary of processed images", true);
Dialog.show();

// Get the parameters
input_dir = Dialog.getString();
output_dir = Dialog.getString();
default_min_size = Dialog.getNumber();
default_max_size = Dialog.getNumber();
default_threshold_ratio = Dialog.getNumber();
default_blur_radius = Dialog.getNumber();
outline_color = Dialog.getChoice();
generate_stack = Dialog.getCheckbox();

// Make sure output directory ends with a file separator
if (!endsWith(output_dir, File.separator)) {
    output_dir = output_dir + File.separator;
}

// Initialize the batch results array
batch_filenames = newArray(0);
batch_areas = newArray(0);
batch_counts = newArray(0);
batch_min_sizes = newArray(0);
batch_max_sizes = newArray(0);
batch_thresholds = newArray(0);
batch_blur_radii = newArray(0);

// Create array to store processed image paths for PDF
processed_image_paths = newArray(0);

// Process files
file_list = getFileList(input_dir);
for (i = 0; i < file_list.length; i++) {
    if (endsWith(file_list[i], ".tif") || endsWith(file_list[i], ".jpg") ||
        endsWith(file_list[i], ".png") || endsWith(file_list[i], ".TIF")) {

        // Open image
        open(input_dir + File.separator + file_list[i]);
        current_image = getTitle();

        // Set initial parameters for this image
        min_size = default_min_size;
        max_size = default_max_size;
        threshold_ratio = default_threshold_ratio;
        blur_radius = default_blur_radius;

        // Interactive parameter adjustment loop
        satisfied = false;
        while (!satisfied) {
            // Close all windows except the original image
            window_titles = getList("image.titles");
            for (w = 0; w < window_titles.length; w++) {
                if (window_titles[w] != current_image) {
                    selectWindow(window_titles[w]);
                    close();
                }
            }

            // Reset ROI Manager
            if (isOpen("ROI Manager")) {
                roiManager("reset");
            }

            // Create a duplicate for processing
            selectWindow(current_image);
            run("Duplicate...", "title=Processing");

            // Convert to 8-bit if not already
            run("8-bit");

            // Create a background image by applying a Gaussian blur
            run("Duplicate...", "title=Background");
            run("Gaussian Blur...", "sigma=" + blur_radius);

            // Create a ratio image (original/background) to normalize for uneven illumination
            imageCalculator("Divide create 32-bit", "Processing", "Background");
            resultTitle = getTitle();

            // Set threshold based on percentage of background
            setThreshold(0, threshold_ratio);
            run("Convert to Mask");

            // Clean up the binary image
            run("Despeckle");
            run("Fill Holes");

            // Analyze particles
            run("Clear Results");
            run("Set Measurements...", "area redirect=None decimal=3");
            run("Analyze Particles...", "size=" + min_size + "-" + max_size + " circularity=0.00-1.00 display clear include summarize add");

            // Get results for this image
            total_area = 0;
            particles_count = 0;

            if (nResults > 0) {
                for (j = 0; j < nResults; j++) {
                    total_area += getResult("Area", j);
                }
                particles_count = nResults;
            }

            // Generate processed image with outlines
            selectWindow(current_image);
            run("Duplicate...", "title=Processed_Image");
            if (roiManager("count") > 0) {
                roiManager("Set Color", outline_color);
                roiManager("Set Line Width", 2);
                roiManager("Draw");

                // Add a scale bar if possible
                run("Scale Bar...", "width=100 height=5 font=14 color=White background=None location=[Lower Right] bold");
            }

            // Ask user if they want to adjust parameters or proceed
            Dialog.create("Adjust parameters for: " + file_list[i]);
            Dialog.addMessage("Image " + (i+1) + " of " + file_list.length + ": " + file_list[i]);
            Dialog.addMessage("Current results: " + particles_count + " particles, total area: " + total_area);
            Dialog.addNumber("Minimum size (pixels)", min_size);
            Dialog.addNumber("Maximum size (pixels)", max_size);
            Dialog.addNumber("Threshold ratio", threshold_ratio);
            Dialog.addNumber("Blur radius", blur_radius);
            Dialog.addChoice("Outline color", newArray("yellow", "red", "green", "blue", "magenta", "cyan"), outline_color);
            Dialog.addCheckbox("Skip this image", false);
            Dialog.addCheckbox("I'm satisfied with these results", false);
            Dialog.show();

            // Get user's choices
            min_size = Dialog.getNumber();
            max_size = Dialog.getNumber();
            threshold_ratio = Dialog.getNumber();
            blur_radius = Dialog.getNumber();
            outline_color = Dialog.getChoice();
            skip_image = Dialog.getCheckbox();
            satisfied = Dialog.getCheckbox();

            if (skip_image) {
                satisfied = true; // Exit the loop
                skip_image = true;
            }
        }

        // If user chose to skip this image
        if (skip_image) {
            run("Close All");
            continue;
        }

        // Add to batch results arrays
        batch_filenames = Array.concat(batch_filenames, file_list[i]);
        batch_areas = Array.concat(batch_areas, total_area);
        batch_counts = Array.concat(batch_counts, particles_count);
        batch_min_sizes = Array.concat(batch_min_sizes, min_size);
        batch_max_sizes = Array.concat(batch_max_sizes, max_size);
        batch_thresholds = Array.concat(batch_thresholds, threshold_ratio);
        batch_blur_radii = Array.concat(batch_blur_radii, blur_radius);

        // Save the processed image with outlines
        if (isOpen("Processed_Image")) {
            selectWindow("Processed_Image");
            // Add text with filename and measurements
            setFont("SansSerif", 14, "bold antialiased");
            setColor("white");
            drawString("File: " + file_list[i] + " | Particles: " + particles_count + " | Area: " + d2s(total_area, 2), 10, 25);

            // Save the processed image
            processed_path = output_dir + "processed_" + file_list[i];
            saveAs("Tiff", processed_path);

            // Add to the list of processed images for PDF
            if (generate_stack) {
                processed_image_paths = Array.concat(processed_image_paths, processed_path);
            }
        }

        // Save the results for this image
        if (nResults > 0) {
            saveAs("Results", output_dir + "results_" + file_list[i] + ".csv");
        }

        // Clean up
        run("Close All");
        if (isOpen("ROI Manager")) {
            selectWindow("ROI Manager");
            run("Close");
        }
    }
}

// Save the batch results to CSV
if (batch_filenames.length > 0) {
    // Create a new results table for batch results
    run("Clear Results");
    for (i = 0; i < batch_filenames.length; i++) {
        setResult("Filename", i, batch_filenames[i]);
        setResult("Total Area", i, batch_areas[i]);
        setResult("Particles Count", i, batch_counts[i]);
        setResult("Min Size Used", i, batch_min_sizes[i]);
        setResult("Max Size Used", i, batch_max_sizes[i]);
        setResult("Threshold Used", i, batch_thresholds[i]);
        setResult("Blur Radius Used", i, batch_blur_radii[i]);
    }
    updateResults();
    saveAs("Results", output_dir + "batch_summary.csv");
}

// Generate stack if requested
if (generate_stack && processed_image_paths.length > 0) {
    // Create a stacką using the processed images
    run("Close All");

    // Open all processed images
    for (i = 0; i < processed_image_paths.length; i++) {
        open(processed_image_paths[i]);
    }

    run("Images to Stack", "name=Processed_Stack title=processed_ use");
    saveAs("Tiff", output_dir + "all_processed_stack.tif");

    // Clean up
    run("Close All");
}
